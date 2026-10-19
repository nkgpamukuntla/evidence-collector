variable "name_prefix" { type = string }
variable "region" { type = string }
variable "partition" { type = string }

variable "image_tag" {
  description = "Tag in the ECR repo; 'unset' until the first image is pushed."
  type        = string
}

variable "components" {
  description = "Long-running services sharing the image."
  type = map(object({
    cpu               = number
    memory            = number
    desired           = number
    subnet_ids        = list(string)
    security_group_id = string
    role_arn          = string
    command           = list(string)
    # Optional: behind a load balancer, and env vars only this component needs.
    target_group_arn = optional(string)
    container_port   = optional(number)
    extra_env        = optional(list(object({ name = string, value = string })), [])
    # Optional: run as a scheduled one-off task instead of (or as well as) a service, e.g. "rate(6 hours)".
    schedule = optional(string)
  }))
}

variable "common_env" {
  type = list(object({ name = string, value = string }))
}

variable "db_bootstrap_command" { type = list(string) }
variable "db_master_secret_arn" { type = string }

variable "log_retention_days" { type = number }

variable "ecr_keep_images" {
  type    = number
  default = 10
}
