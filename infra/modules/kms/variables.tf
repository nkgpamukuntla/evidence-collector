variable "name_prefix" { type = string }
variable "region" { type = string }

variable "tenant_ids" {
  description = "One raw key per tenant."
  type        = list(string)
}

variable "deletion_window_days" { type = number }

variable "key_admin_principal_arns" {
  description = "Manage, never use (R4). Must include the principal running apply."
  type        = list(string)
}

variable "worker_role_arn" { type = string }
variable "evaluator_role_arn" { type = string }
variable "terminator_role_arn" { type = string }

variable "secret_writer_principal_arns" {
  type    = list(string)
  default = []
}

variable "raw_bucket_arn" { type = string }
variable "source_secret_arn_pattern" { type = string }
