# Image build without local Docker: scripts/build-image.ps1 (app repo) uploads a zip of a
# committed revision here, and an ARM CodeBuild project builds and pushes linux/arm64 (R8).
# Triggered by hand from a workstation; there is no pipeline.
resource "aws_s3_bucket" "source" {
  bucket        = "${var.name_prefix}-build-src-${var.account_id}"
  force_destroy = true # only transient source zips live here
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    id     = "expire-source-zips"
    status = "Enabled"
    filter {}
    expiration { days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

resource "aws_s3_bucket_policy" "source" {
  bucket     = aws_s3_bucket.source.id
  depends_on = [aws_s3_bucket_public_access_block.source]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.name_prefix}-app-build"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "build" {
  name = "${var.name_prefix}-app-build"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "build" {
  name = "build-and-push"
  role = aws_iam_role.build.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSource"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Sid      = "KeepCodeSigningCertificate"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.source.arn}/codesign/*"
      },
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushToCollectorRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
          "ecr:PutImage", "ecr:UploadLayerPart",
        ]
        Resource = var.ecr_repository_arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.build.arn}:*"
      },
    ]
  })
}

resource "aws_codebuild_project" "app" {
  name           = "${var.name_prefix}-app-build"
  service_role   = aws_iam_role.build.arn
  build_timeout  = 30
  queued_timeout = 60

  source {
    type     = "S3"
    location = "${aws_s3_bucket.source.id}/src/placeholder.zip" # overridden per build
  }

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    type            = "ARM_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux-aarch64-standard:3.0"
    privileged_mode = true # docker build
    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = var.ecr_repository_url
    }
    environment_variable {
      name  = "CODESIGN_KEY_ID"
      value = aws_kms_key.codesign.key_id
    }
    environment_variable {
      name  = "SOURCE_BUCKET"
      value = aws_s3_bucket.source.id
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}

# ---------- code signing: the offline collector's Authenticode signature ----------
# RSA-3072 in KMS (R3: no private key on disk). Only this build signs, only with
# PKCS#1 v1.5 SHA-256; administrators manage the key but cannot use it (R4).
# The self-signed certificate over it is made once by the build and kept under codesign/
# in the source bucket. A commercial certificate later reuses this key via a CSR.
resource "aws_kms_key" "codesign" {
  description              = "${var.name_prefix} collector code signing (Authenticode)"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_3072"
  deletion_window_in_days  = var.deletion_window_days
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = var.key_admin_principal_arns }
        Action = [
          "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias",
          "kms:Describe*", "kms:Get*", "kms:List*",
          "kms:EnableKey", "kms:DisableKey",
          "kms:PutKeyPolicy", "kms:UpdateKeyDescription",
          "kms:TagResource", "kms:UntagResource",
          "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:RevokeGrant",
        ]
        Resource = "*"
      },
      {
        Sid       = "BuildSigns"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.build.arn }
        Action    = ["kms:Sign"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:SigningAlgorithm" = "RSASSA_PKCS1_V1_5_SHA_256" } }
      },
      {
        Sid       = "BuildReadsPublicKey"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.build.arn }
        Action    = ["kms:GetPublicKey", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "codesign" {
  name          = "alias/${var.name_prefix}-codesign"
  target_key_id = aws_kms_key.codesign.key_id
}
