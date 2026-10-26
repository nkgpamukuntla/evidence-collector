# Five kinds of key, one job each. R4: every key policy is the only authority over its
# key: no statement names the account root, admins manage but never use, and nobody
# is given kms:CreateGrant.
locals {
  kms_admin_actions = [
    "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias",
    "kms:Describe*", "kms:Get*", "kms:List*",
    "kms:EnableKey", "kms:EnableKeyRotation", "kms:DisableKey", "kms:DisableKeyRotation",
    "kms:PutKeyPolicy", "kms:UpdateKeyDescription",
    "kms:TagResource", "kms:UntagResource",
    "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:RevokeGrant",
  ]

  admin_statement = {
    Sid       = "KeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = var.key_admin_principal_arns }
    Action    = local.kms_admin_actions
    Resource  = "*"
  }

  s3_via = "s3.${var.region}.amazonaws.com"
  sm_via = "secretsmanager.${var.region}.amazonaws.com"
}

# ---------- raw[tenant]: seals one tenant's bundles, bound to its prefix ----------
resource "aws_kms_key" "raw" {
  for_each                = toset(var.tenant_ids)
  description             = "${var.name_prefix} raw bundles, tenant ${each.key}"
  key_usage               = "ENCRYPT_DECRYPT"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_days
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.admin_statement,
      {
        Sid       = "WorkerSealsViaS3"
        Effect    = "Allow"
        Principal = { AWS = var.worker_role_arn }
        Action    = ["kms:GenerateDataKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = local.s3_via }
          StringLike   = { "kms:EncryptionContext:aws:s3:arn" = "${var.raw_bucket_arn}/${each.key}/*" }
        }
      },
      {
        Sid       = "EvaluatorOpensViaS3"
        Effect    = "Allow"
        Principal = { AWS = var.evaluator_role_arn }
        Action    = ["kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = local.s3_via }
          StringLike   = { "kms:EncryptionContext:aws:s3:arn" = "${var.raw_bucket_arn}/${each.key}/*" }
        }
      },
      {
        Sid       = "TerminatorShreds"
        Effect    = "Allow"
        Principal = { AWS = var.terminator_role_arn }
        Action    = ["kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "raw" {
  for_each      = aws_kms_key.raw
  name          = "alias/${var.name_prefix}-raw-${each.key}"
  target_key_id = each.value.key_id
}

# ---------- collector[tenant]: opens offline-collector bundles for one office ----------
# Asymmetric: the collector, run on a county PC with no AWS access, wraps each bundle's
# content key with this key's public half (RSA-OAEP-SHA-256). Only the portal may unwrap,
# only with that algorithm. Asymmetric keys cannot rotate; a new key means a new download.
resource "aws_kms_key" "collector" {
  for_each                 = toset(var.tenant_ids)
  description              = "${var.name_prefix} collector bundles, tenant ${each.key}"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "RSA_3072"
  deletion_window_in_days  = var.deletion_window_days
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.admin_statement,
      {
        Sid       = "PortalReadsPublicKey"
        Effect    = "Allow"
        Principal = { AWS = var.portal_role_arn }
        Action    = ["kms:GetPublicKey", "kms:DescribeKey"]
        Resource  = "*"
      },
      {
        Sid       = "PortalOpensBundles"
        Effect    = "Allow"
        Principal = { AWS = var.portal_role_arn }
        Action    = ["kms:Decrypt"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:EncryptionAlgorithm" = "RSAES_OAEP_SHA_256" } }
      },
      {
        Sid       = "TerminatorShreds"
        Effect    = "Allow"
        Principal = { AWS = var.terminator_role_arn }
        Action    = ["kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "collector" {
  for_each      = aws_kms_key.collector
  name          = "alias/${var.name_prefix}-collector-${each.key}"
  target_key_id = each.value.key_id
}

# ---------- signing: RSA-2048, the Microsoft client assertion (RS256 only) ----------
resource "aws_kms_key" "signing" {
  description              = "${var.name_prefix} Microsoft client-assertion signing (RS256)"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_2048"
  deletion_window_in_days  = var.deletion_window_days
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.admin_statement,
      {
        Sid       = "WorkerSignsRS256"
        Effect    = "Allow"
        Principal = { AWS = var.worker_role_arn }
        Action    = ["kms:Sign"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:SigningAlgorithm" = "RSASSA_PKCS1_V1_5_SHA_256" } }
      },
      {
        Sid       = "WorkerReadsPublicKey"
        Effect    = "Allow"
        Principal = { AWS = var.worker_role_arn }
        Action    = ["kms:GetPublicKey", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "signing" {
  name          = "alias/${var.name_prefix}-signing"
  target_key_id = aws_kms_key.signing.key_id
}

# ---------- fingerprint: HMAC-256 over the credential, recorded on every exchange ----------
resource "aws_kms_key" "fingerprint" {
  description              = "${var.name_prefix} credential fingerprint (HMAC-256)"
  key_usage                = "GENERATE_VERIFY_MAC"
  customer_master_key_spec = "HMAC_256"
  deletion_window_in_days  = var.deletion_window_days
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.admin_statement,
      {
        Sid       = "WorkerGeneratesMac"
        Effect    = "Allow"
        Principal = { AWS = var.worker_role_arn }
        Action    = ["kms:GenerateMac"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:MacAlgorithm" = "HMAC_SHA_256" } }
      },
    ]
  })
}

resource "aws_kms_alias" "fingerprint" {
  name          = "alias/${var.name_prefix}-fingerprint"
  target_key_id = aws_kms_key.fingerprint.key_id
}

# ---------- secrets: source credentials under ec/<env>/source/ (R5) ----------
resource "aws_kms_key" "secrets" {
  description             = "${var.name_prefix} source credentials in Secrets Manager"
  key_usage               = "ENCRYPT_DECRYPT"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_days
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        local.admin_statement,
        {
          Sid       = "WorkerReadsSourceCredentials"
          Effect    = "Allow"
          Principal = { AWS = var.worker_role_arn }
          Action    = ["kms:Decrypt"]
          Resource  = "*"
          Condition = {
            StringEquals = { "kms:ViaService" = local.sm_via }
            StringLike   = { "kms:EncryptionContext:SecretARN" = var.source_secret_arn_pattern }
          }
        },
      ],
      length(var.secret_writer_principal_arns) == 0 ? [] : [{
        Sid       = "OnboardingWritesSourceCredentials"
        Effect    = "Allow"
        Principal = { AWS = var.secret_writer_principal_arns }
        Action    = ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = local.sm_via }
          StringLike   = { "kms:EncryptionContext:SecretARN" = var.source_secret_arn_pattern }
        }
      }],
    )
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
