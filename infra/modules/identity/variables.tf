variable "name_prefix" { type = string }
variable "account_id" { type = string }

variable "raw_bucket_arn" {
  description = "ARN of the raw-bundle bucket (a string, so roles can exist before the bucket)."
  type        = string
}

variable "source_secret_arn_pattern" {
  description = "Secrets Manager ARN pattern for source credentials (ec/<env>/source/*)."
  type        = string
}

variable "heartbeat_namespace" {
  description = "CloudWatch namespace the worker may publish the liveness heartbeat to."
  type        = string
}

variable "terminator_principal_arns" {
  description = "Humans allowed to assume the terminator role."
  type        = list(string)
}
