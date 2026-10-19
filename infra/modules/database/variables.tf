variable "name_prefix" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "partition" { type = string }

variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }

variable "engine_version" {
  description = "PostgreSQL 16 minor (R9)."
  type        = string
  validation {
    condition     = startswith(var.engine_version, "16.")
    error_message = "PostgreSQL 16 only (R9)."
  }
}

variable "instance_class" { type = string }
variable "allocated_storage" { type = number }
variable "multi_az" { type = bool }

variable "kms_key_arn" {
  description = "null = AWS-managed aws/rds key (Option B)."
  type        = string
  default     = null
}

variable "backup_retention_days" { type = number }
variable "deletion_protection" { type = bool }

variable "iam_db_users" {
  description = "IAM role name => Postgres user it may log in as with IAM auth."
  type        = map(string)
}
