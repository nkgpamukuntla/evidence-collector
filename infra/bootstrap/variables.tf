variable "region" {
  type = string
}

variable "environment" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.environment))
    error_message = "2-12 lowercase letters or digits."
  }
}

variable "key_admin_principal_arns" {
  description = "Humans who administer the state key. MUST include the principal running this apply (KMS lockout check). The break-glass key-admin role is added automatically."
  type        = list(string)
}

variable "state_user_principal_arns" {
  description = "Humans allowed to read/write Terraform state (deploys run from a workstation)."
  type        = list(string)
}

variable "key_admin_assumer_arn_patterns" {
  description = "ARN patterns allowed to assume the break-glass key-admin role, e.g. the SSO admin role with a * suffix."
  type        = list(string)
}

variable "trail_retention_days" {
  description = "Days CloudTrail log files are kept in this account's trail bucket (the org trail keeps its own copy)."
  type        = number
  default     = 365
  validation {
    condition     = var.trail_retention_days >= 90
    error_message = "Keep at least 90 days of audit logs."
  }
}

variable "state_noncurrent_days" {
  description = "Days superseded Terraform state versions are kept."
  type        = number
  default     = 90
}

variable "alert_email" {
  description = "Optional email subscribed to security alerts (KMS policy changes). Empty = no subscription."
  type        = string
  default     = ""
}
