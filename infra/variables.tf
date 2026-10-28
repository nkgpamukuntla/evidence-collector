# Core inputs (handover section 4). Hosting additions live in hosting_variables.tf.
variable "region" {
  description = "One region; a KMS key lives in one region."
  type        = string
}

variable "environment" {
  description = "Carried in every resource name (ec-<env>-...)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.environment))
    error_message = "2-12 lowercase letters or digits."
  }
}

variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 4 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Two to four distinct zones."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "/20 or larger."
  }
}

variable "tenant_ids" {
  description = "The collector's own tenant ids (lowercase UUIDs). One raw key and one bucket-policy statement each."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.tenant_ids) <= 36 && alltrue([for t in var.tenant_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", t))])
    error_message = "Lowercase UUIDs, 36 at most (bucket policy size limit)."
  }
}

variable "raw_retention_days" {
  description = "Object Lock (governance) period for raw bundles."
  type        = number
  default     = 90
  validation {
    condition     = var.raw_retention_days >= 1 && var.raw_retention_days <= 395
    error_message = "1-395 days."
  }
}

variable "key_deletion_window_days" {
  description = "The undo window for a shred."
  type        = number
  default     = 30
  validation {
    condition     = var.key_deletion_window_days >= 7 && var.key_deletion_window_days <= 30
    error_message = "7-30 days (AWS limits)."
  }
}

variable "key_admin_principal_arns" {
  description = "Manage keys, never use them (R4). Must include the principal running apply, or KMS rejects the policy as a lockout."
  type        = list(string)
  validation {
    condition     = length(var.key_admin_principal_arns) >= 1
    error_message = "At least one key administrator."
  }
}

variable "terminator_principal_arns" {
  description = "Humans allowed to assume the terminator role (MFA)."
  type        = list(string)
  validation {
    condition     = length(var.terminator_principal_arns) >= 1
    error_message = "At least one terminator principal."
  }
}

variable "secret_writer_principal_arns" {
  description = "Onboarding principals that write source credentials under ec/<env>/source/. May be empty."
  type        = list(string)
  default     = []
}

variable "liveness_period_minutes" {
  description = "How often a collection tick is expected to finish."
  type        = number
  default     = 5
}

variable "liveness_grace_periods" {
  description = "Silent periods before the alarm fires."
  type        = number
  default     = 2
  validation {
    condition     = var.liveness_grace_periods >= 2 && var.liveness_grace_periods <= 5
    error_message = "2-5."
  }
}

variable "liveness_alarm_enabled" {
  description = "R10: keep false until the process that publishes the heartbeat is running."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for every log group (cost)."
  type        = number
  default     = 14
}

# ---------- hosting ----------
variable "nat_gateway_count" {
  description = "1 for dev, one per AZ for prod. ~$33/month each."
  type        = number
  default     = 1
  validation {
    condition     = var.nat_gateway_count >= 1 && var.nat_gateway_count <= length(var.availability_zones)
    error_message = "1 to the number of availability zones (one public subnet per AZ)."
  }
}

variable "endpoint_az_count" {
  description = "AZs that carry interface endpoints (1 dev, 2 prod). Each endpoint costs per AZ-hour."
  type        = number
  default     = 1
  validation {
    condition     = var.endpoint_az_count >= 1 && var.endpoint_az_count <= length(var.availability_zones)
    error_message = "1 to the number of availability zones."
  }
}

variable "interface_endpoints" {
  description = "Interface endpoints in the evaluator subnets. ecr.api, ecr.dkr, logs and kms are required; add secretsmanager/monitoring in prod to keep the worker's AWS calls off NAT."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs", "kms"]
}

variable "worker_allowed_domains" {
  description = "Domains the VPC resolver will answer. Everything else gets NODATA."
  type        = list(string)
  default = [
    "login.microsoftonline.com",
    "graph.microsoft.com",
    "amazonaws.com", "*.amazonaws.com", "*.api.aws",
    "*.amazoncognito.com", # portal sign-in token exchange
  ]
}

variable "heartbeat_domain" {
  description = "External deadman host, e.g. hc-ping.com. Empty until chosen."
  type        = string
  default     = ""
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
  description = "One-off task: migrations + CONNECT grants."
  type        = list(string)
  default     = ["python", "-m", "app.migrate", "--dir", "migrations"]
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
  default     = "16.15"
}

variable "db_kms_key_arn" {
  description = "null = AWS-managed aws/rds key (Option B). A customer key needs Tim's decision on R4 (Option A)."
  type        = string
  default     = null
}

variable "db_worker_user" {
  description = "Postgres role the worker logs in as with IAM auth (created by the migrations, GRANT rds_iam)."
  type        = string
  default     = "ec_worker"
}

variable "db_evaluator_user" {
  description = "Postgres role the evaluator logs in as with IAM auth (created by the migrations, GRANT rds_iam)."
  type        = string
  default     = "ec_evaluator"
}

# ---------- portal ----------
variable "portal_desired_count" {
  description = "Portal tasks once an image exists (forced to 0 while envs/<env>.image is 'unset')."
  type        = number
  default     = 1
}

variable "portal_cpu" {
  type    = number
  default = 256
}

variable "portal_memory" {
  type    = number
  default = 512
}

variable "portal_admin_emails" {
  description = "Initial platform administrators; Cognito emails each a temporary password."
  type        = list(string)
  default     = []
}

variable "portal_allowed_countries" {
  description = "CloudFront geo allowlist for the portal (ISO 3166-1 alpha-2)."
  type        = list(string)
  default     = ["US"]
}

# ---------- Microsoft source (Phase 2) ----------
# None of these is a secret: the private key never leaves KMS (R3).
variable "ms_client_id" {
  description = "Application (client) ID of the multi-tenant app registration. Empty = collection off."
  type        = string
  default     = ""
}

variable "ms_cert_thumbprint_sha1" {
  description = "x5t (base64url SHA-1) of the certificate uploaded to the app registration."
  type        = string
  default     = ""
}

variable "ms_cert_thumbprint_sha256" {
  description = "x5t#S256 of the same certificate."
  type        = string
  default     = ""
}

variable "collection_schedule" {
  description = "When the worker checks for due offices (EventBridge Scheduler expression, UTC). Hourly: each office is scanned once a day at the end of its own business day, in its own time zone (app/schedule.py); runs with nothing due exit in seconds."
  type        = string
  default     = "cron(5 * * * ? *)"
}

variable "evaluation_schedule" {
  description = "When the evaluator scores new bundles; 20 minutes after each worker check. It only opens runs not yet evaluated."
  type        = string
  default     = "cron(25 * * * ? *)"
}
