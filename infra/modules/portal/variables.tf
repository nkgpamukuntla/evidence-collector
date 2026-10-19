variable "name_prefix" { type = string }
variable "account_id" { type = string }
variable "vpc_id" { type = string }

variable "alb_subnet_ids" {
  description = "Private subnets for the internal ALB (two AZs)."
  type        = list(string)
}

variable "alb_sg_id" { type = string }

variable "container_port" {
  type    = number
  default = 8000
}

variable "allowed_countries" {
  description = "CloudFront geo allowlist (ISO 3166-1 alpha-2); empty = no geo restriction."
  type        = list(string)
}

variable "admin_emails" {
  description = "Initial platform administrators; Cognito emails each a temporary password."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  type    = bool
  default = false
}
