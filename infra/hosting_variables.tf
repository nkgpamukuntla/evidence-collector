variable "nat_gateway_count" {
  description = "1 for dev, one per AZ for prod."
  type        = number
  default     = 1
  validation {
    condition     = var.nat_gateway_count >= 1 && var.nat_gateway_count <= 3
    error_message = "1-3."
  }
}

variable "endpoint_az_count" {
  description = "AZs that carry interface endpoints (1 dev, 2 prod)."
  type        = number
  default     = 1
}

variable "worker_cpu" {
  type    = number
  default = 256
}

variable "worker_memory" {
  type    = number
  default = 512
}

variable "evaluator_cpu" {
  type    = number
  default = 512
}

variable "evaluator_memory" {
  type    = number
  default = 1024
}

variable "worker_desired_count" {
  description = "Keep 0 until the process entry point exists (R10)."
  type        = number
  default     = 0
}

variable "evaluator_desired_count" {
  type    = number
  default = 0
}

variable "worker_command" {
  description = "Container command; empty = image default."
  type        = list(string)
  default     = []
}

variable "evaluator_command" {
  type    = list(string)
  default = []
}

variable "db_bootstrap_command" {
  description = "One-off task: migrations + CONNECT grants (prod-safe tool still to be written)."
  type        = list(string)
  default     = ["python", "tools/migrate.py", "--dir", "migrations"]
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_engine_version" {
  description = "PostgreSQL 16 minor (R9)."
  type        = string
  validation {
    condition     = startswith(var.db_engine_version, "16")
    error_message = "PostgreSQL 16 only (R9)."
  }
}

variable "db_kms_key_arn" {
  description = "null = AWS-managed aws/rds key (Option B). A customer key needs Tim's decision on R4 (Option A)."
  type        = string
  default     = null
}

variable "worker_allowed_domains" {
  description = "Domains the VPC resolver will answer. Everything else gets NODATA."
  type        = list(string)
  default = [
    "login.microsoftonline.com",
    "graph.microsoft.com",
    "amazonaws.com", "*.amazonaws.com", "*.api.aws",
  ]
}

variable "heartbeat_domain" {
  description = "External deadman host, e.g. hc-ping.com. Empty until chosen."
  type        = string
  default     = ""
}
