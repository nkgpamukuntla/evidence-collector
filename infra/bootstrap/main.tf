data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "ec-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Deployment is from a workstation (no CI role), so state users are humans only.
  key_admins        = concat(var.key_admin_principal_arns, [aws_iam_role.key_admin.arn])
  bucket_principals = distinct(concat(local.key_admins, var.state_user_principal_arns))

  # R4: admins manage, never use. No kms:CreateGrant, no wildcard that includes it.
  kms_admin_actions = [
    "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias",
    "kms:Describe*", "kms:Get*", "kms:List*",
    "kms:EnableKey", "kms:EnableKeyRotation", "kms:DisableKey", "kms:DisableKeyRotation",
    "kms:PutKeyPolicy", "kms:UpdateKeyDescription",
    "kms:TagResource", "kms:UntagResource",
    "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:RevokeGrant",
  ]
}

# ---------- Break-glass key administrator ----------
# Key policies have no root delegation (R4), so a key whose only admin is an SSO role
# becomes unmanageable if Identity Center re-provisions that role under a new ARN.
# This role has a stable ARN and is assumable by any principal matching the pattern
# (e.g. the SSO admin role, whatever its suffix). It can repair key and bucket policies.
resource "aws_iam_role" "key_admin" {
  name                 = "${local.name}-key-admin"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { ArnLike = { "aws:PrincipalArn" = var.key_admin_assumer_arn_patterns } }
    }]
  })
}

resource "aws_iam_role_policy" "key_admin_repair" {
  name = "repair-state-bucket-policy"
  role = aws_iam_role.key_admin.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy"]
      Resource = "arn:${local.partition}:s3:::${local.name}-tfstate-${local.account_id}"
    }]
  })
}
