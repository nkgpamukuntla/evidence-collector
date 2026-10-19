variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "account_id" { type = string }

variable "namespace" { type = string }
variable "metric_name" { type = string }

variable "period_minutes" { type = number }

variable "grace_periods" {
  type = number
  validation {
    condition     = var.grace_periods >= 2 && var.grace_periods <= 5
    error_message = "2-5."
  }
}

variable "alarm_enabled" {
  description = "R10: false until the heartbeat publisher is running."
  type        = bool
  default     = false
}
