variable "name_prefix" { type = string }
variable "account_id" { type = string }
variable "ecr_repository_url" { type = string }
variable "ecr_repository_arn" { type = string }
variable "log_retention_days" { type = number }

variable "key_admin_principal_arns" {
  description = "Manage the code-signing key, never use it (R4)."
  type        = list(string)
}
variable "deletion_window_days" { type = number }
