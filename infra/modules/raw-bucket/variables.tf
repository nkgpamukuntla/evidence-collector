variable "bucket_name" { type = string }

variable "tenant_ids" { type = list(string) }

variable "raw_key_arns" {
  description = "tenant id => raw key ARN (from modules/kms)."
  type        = map(string)
}

variable "terminator_role_arn" { type = string }

variable "retention_days" {
  description = "Object Lock governance period."
  type        = number
}
