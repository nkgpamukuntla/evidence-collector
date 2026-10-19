data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name        = "ec-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  state_users = concat(var.state_user_principal_arns, [aws_iam_role.gha_apply.arn])
  bucket_principals = distinct(concat(var.key_admin_principal_arns, local.state_users))

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

# ---------- GitHub OIDC + CI apply role (no long-lived keys) ----------
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_role" "gha_apply" {
  name                 = "${local.name}-gha-apply"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Only jobs bound to the matching GitHub Environment (which carries required reviewers).
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${var.environment}"
        }
      }
    }]
  })
}

# TODO(review with Tim): replace with a scoped policy once the resource set is stable.
resource "aws_iam_role_policy_attachment" "gha_apply_admin" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}
