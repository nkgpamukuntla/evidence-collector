# Raw-bundle bucket: Object Lock (governance) for retention_days, versioned, never
# public, and a policy tying each tenant's prefix to that tenant's key.
# Bucket Keys stay off so each object's encryption context names its own prefix,
# which is what binds the key to the tenant (modules/kms). Cost: one KMS request per bundle.
# No multipart: a single PUT (up to 5 GB) needs only kms:GenerateDataKey.
resource "aws_s3_bucket" "raw" {
  bucket              = var.bucket_name
  object_lock_enabled = true
}

resource "aws_s3_bucket_ownership_controls" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration { status = "Enabled" }
}

# Governance, not compliance: termination must be able to delete (terminator only).
resource "aws_s3_bucket_object_lock_configuration" "raw" {
  bucket     = aws_s3_bucket.raw.id
  depends_on = [aws_s3_bucket_versioning.raw]
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.retention_days
    }
  }
}

# The default only applies to a PUT the policy would refuse anyway; the tenant key is enforced below.
resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket     = aws_s3_bucket.raw.id
  depends_on = [aws_s3_bucket_versioning.raw]
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

locals {
  arn                = aws_s3_bucket.raw.arn
  tenant_prefix_arns = [for t in var.tenant_ids : "${local.arn}/${t}/*"]

  base_statements = [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.arn, "${local.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    },
    {
      Sid       = "OnlyTerminatorReachesInsideLock"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["s3:BypassGovernanceRetention", "s3:PutObjectRetention"]
      Resource  = [local.arn, "${local.arn}/*"]
      Condition = { ArnNotEquals = { "aws:PrincipalArn" = var.terminator_role_arn } }
    },
  ]

  # With no tenants every PUT is refused; otherwise anything outside a tenant prefix is.
  outside_statement = length(local.tenant_prefix_arns) == 0 ? jsonencode({
    Sid       = "DenyPutOutsideTenantPrefixes"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:PutObject"
    Resource  = "${local.arn}/*"
    }) : jsonencode({
    Sid         = "DenyPutOutsideTenantPrefixes"
    Effect      = "Deny"
    Principal   = "*"
    Action      = "s3:PutObject"
    NotResource = local.tenant_prefix_arns
  })

  # ~510 bytes per tenant; AWS caps bucket policies at 20 KB, hence the 36-tenant limit.
  tenant_statements = [for t in var.tenant_ids : {
    Sid       = "Tenant${replace(t, "-", "")}"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:PutObject"
    Resource  = "${local.arn}/${t}/*"
    Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption-aws-kms-key-id" = var.raw_key_arns[t] } }
  }]
}

resource "aws_s3_bucket_policy" "raw" {
  bucket     = aws_s3_bucket.raw.id
  depends_on = [aws_s3_bucket_public_access_block.raw]
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.base_statements, [jsondecode(local.outside_statement)], local.tenant_statements)
  })
}
