variable "name_prefix" { type = string }
variable "region" { type = string }
variable "partition" { type = string }

variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 4
    error_message = "Two to four zones (each tier has four netnums)."
  }
}

variable "vpc_cidr" { type = string }

variable "nat_gateway_count" {
  type = number
  validation {
    condition     = var.nat_gateway_count >= 1
    error_message = "At least one NAT gateway (the worker reaches Microsoft through it)."
  }
}

variable "endpoint_az_count" { type = number }

variable "interface_endpoints" {
  type = list(string)
  validation {
    condition     = length(setsubtract(["ecr.api", "ecr.dkr", "logs", "kms"], var.interface_endpoints)) == 0
    error_message = "Must include ecr.api, ecr.dkr, logs and kms (the evaluator cannot start or decrypt without them)."
  }
}

variable "raw_bucket_arn" {
  description = "The only bucket the S3 gateway endpoint admits (besides ECR layers)."
  type        = string
}

variable "worker_allowed_domains" { type = list(string) }

variable "heartbeat_domain" {
  type    = string
  default = ""
}

variable "portal_port" {
  type    = number
  default = 8000
}
