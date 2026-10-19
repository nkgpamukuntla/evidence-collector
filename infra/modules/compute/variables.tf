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
