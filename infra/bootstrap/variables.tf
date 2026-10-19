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
  description = "Humans who administer the state key. MUST include the principal running this apply (KMS lockout check)."
  type        = list(string)
}

variable "state_user_principal_arns" {
  description = "Humans allowed to read/write Terraform state locally (break-glass). The CI apply role is added automatically."
  type        = list(string)
}

variable "github_repository" {
  description = "owner/repo allowed to assume the CI apply role."
  type        = string
  default     = "timhill220/evidence-collector"
}

variable "create_github_oidc_provider" {
  description = "Only one GitHub OIDC provider may exist per account."
  type        = bool
  default     = true
}
