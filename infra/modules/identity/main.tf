# Three roles. worker writes bundles and cannot read them; evaluator reads them and
# nothing else; terminator is for humans with MFA and is the only thing that can reach
# inside a lock. KMS use is granted in each key's own policy (modules/kms), not here.
data "aws_iam_policy_document" "task_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

# ---------- worker ----------
resource "aws_iam_role" "worker" {
  name               = "${var.name_prefix}-worker"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}

resource "aws_iam_role_policy" "worker" {
  name = "worker"
  role = aws_iam_role.worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteBundles"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        Sid      = "ReadSourceCredentials"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = var.source_secret_arn_pattern
      },
      {
        Sid       = "Heartbeat"
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = var.heartbeat_namespace } }
      },
    ]
  })
}

# ---------- evaluator ----------
resource "aws_iam_role" "evaluator" {
  name               = "${var.name_prefix}-evaluator"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}

resource "aws_iam_role_policy" "evaluator" {
  name = "evaluator"
  role = aws_iam_role.evaluator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadBundles"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        Sid      = "ListBundles"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.raw_bucket_arn
      },
    ]
  })
}

# ---------- terminator (humans, MFA) ----------
# BoolIfExists: IAM users must present MFA; Identity Center sessions carry no MFA key,
# so for them MFA is enforced at sign-in (Identity Center MFA must be "always-on").
resource "aws_iam_role" "terminator" {
  name                 = "${var.name_prefix}-terminator"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.terminator_principal_arns }
      Action    = "sts:AssumeRole"
      Condition = { BoolIfExists = { "aws:MultiFactorAuthPresent" = "true" } }
    }]
  })
}

resource "aws_iam_role_policy" "terminator" {
  name = "terminate-tenant"
  role = aws_iam_role.terminator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DeleteInsideLock"
        Effect = "Allow"
        Action = [
          "s3:BypassGovernanceRetention", "s3:DeleteObject", "s3:DeleteObjectVersion",
          "s3:GetObjectRetention", "s3:PutObjectRetention",
        ]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        Sid      = "ListVersions"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketVersions"]
        Resource = var.raw_bucket_arn
      },
    ]
  })
}

# ---------- portal ----------
# Onboarding writes source credentials (R5: never through Terraform). It can create and
# overwrite them but cannot read them back: no GetSecretValue. Encryption with the secrets
# key is granted in that key's policy (modules/kms, secret writers).
resource "aws_iam_role" "portal" {
  name               = "${var.name_prefix}-portal"
  assume_role_policy = data.aws_iam_policy_document.task_trust.json
}

resource "aws_iam_role_policy" "portal" {
  name = "portal"
  role = aws_iam_role.portal.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteSourceCredentials"
      Effect   = "Allow"
      Action   = ["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:TagResource"]
      Resource = var.source_secret_arn_pattern
    }]
  })
}
