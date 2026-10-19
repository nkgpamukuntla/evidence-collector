# Root stack: one per environment, values from envs/<env>.tfvars and envs/<env>.backend.hcl.
# Module order avoids cycles: identity -> kms -> raw-bucket; network takes the bucket ARN
# as a string; database and compute take ids from network and identity.
locals {
  name_prefix = "ec-${var.environment}"
  is_prod     = var.environment == "prod"

  # Strings, not resource references, so roles and key policies can exist before the bucket.
  raw_bucket_name           = "${local.name_prefix}-raw-${local.account_id}"
  raw_bucket_arn            = "arn:${local.partition}:s3:::${local.raw_bucket_name}"
  source_secret_arn_pattern = "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:ec/${var.environment}/source/*"

  heartbeat_namespace = "EvidenceCollector"
  heartbeat_metric    = "CollectionHeartbeat"

  # Settings every runtime component shares (database login is by IAM token, no password).
  runtime_env = [
    { name = "ENVIRONMENT", value = var.environment },
    { name = "AWS_REGION", value = var.region },
    { name = "DB_IAM_AUTH", value = "true" },
  ]
  # Scheduled collection starts only once the app registration exists and an image is deployed.
  collect = var.ms_client_id != "" && var.ms_cert_thumbprint_sha1 != "" && local.image_tag != "unset"

  image_file = "${path.module}/envs/${var.environment}.image"
  image_tag  = fileexists(local.image_file) ? trimspace(file(local.image_file)) : "unset"
}

module "identity" {
  source                    = "./modules/identity"
  name_prefix               = local.name_prefix
  account_id                = local.account_id
  raw_bucket_arn            = local.raw_bucket_arn
  source_secret_arn_pattern = local.source_secret_arn_pattern
  heartbeat_namespace       = local.heartbeat_namespace
  terminator_principal_arns = var.terminator_principal_arns
}

module "kms" {
  source                       = "./modules/kms"
  name_prefix                  = local.name_prefix
  region                       = var.region
  tenant_ids                   = var.tenant_ids
  deletion_window_days         = var.key_deletion_window_days
  key_admin_principal_arns     = var.key_admin_principal_arns
  worker_role_arn              = module.identity.worker_role_arn
  evaluator_role_arn           = module.identity.evaluator_role_arn
  terminator_role_arn          = module.identity.terminator_role_arn
  secret_writer_principal_arns = concat(var.secret_writer_principal_arns, [module.identity.portal_role_arn])
  raw_bucket_arn               = local.raw_bucket_arn
  source_secret_arn_pattern    = local.source_secret_arn_pattern
}

module "raw_bucket" {
  source              = "./modules/raw-bucket"
  bucket_name         = local.raw_bucket_name
  tenant_ids          = var.tenant_ids
  raw_key_arns        = module.kms.raw_key_arns
  terminator_role_arn = module.identity.terminator_role_arn
  retention_days      = var.raw_retention_days
}

module "network" {
  source                 = "./modules/network"
  name_prefix            = local.name_prefix
  region                 = var.region
  partition              = local.partition
  availability_zones     = var.availability_zones
  vpc_cidr               = var.vpc_cidr
  nat_gateway_count      = var.nat_gateway_count
  endpoint_az_count      = var.endpoint_az_count
  interface_endpoints    = var.interface_endpoints
  raw_bucket_arn         = local.raw_bucket_arn
  worker_allowed_domains = var.worker_allowed_domains
  heartbeat_domain       = var.heartbeat_domain
}

module "database" {
  source                = "./modules/database"
  name_prefix           = local.name_prefix
  region                = var.region
  account_id            = local.account_id
  partition             = local.partition
  subnet_ids            = module.network.db_subnet_ids
  security_group_id     = module.network.db_sg_id
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.db_multi_az
  kms_key_arn           = var.db_kms_key_arn
  backup_retention_days = local.is_prod ? 35 : 1
  deletion_protection   = local.is_prod
  iam_db_users = {
    (module.identity.worker_role_name)    = var.db_worker_user
    (module.identity.evaluator_role_name) = var.db_evaluator_user
    (module.identity.portal_role_name)    = "ec_portal"
  }
}

module "portal" {
  source              = "./modules/portal"
  name_prefix         = local.name_prefix
  account_id          = local.account_id
  vpc_id              = module.network.vpc_id
  alb_subnet_ids      = module.network.worker_subnet_ids
  alb_sg_id           = module.network.alb_sg_id
  allowed_countries   = var.portal_allowed_countries
  admin_emails        = var.portal_admin_emails
  deletion_protection = local.is_prod
}

module "build" {
  source             = "./modules/build"
  name_prefix        = local.name_prefix
  account_id         = local.account_id
  ecr_repository_url = module.compute.ecr_repository_url
  ecr_repository_arn = module.compute.ecr_repository_arn
  log_retention_days = var.log_retention_days
}

module "compute" {
  source               = "./modules/compute"
  name_prefix          = local.name_prefix
  region               = var.region
  partition            = local.partition
  image_tag            = local.image_tag
  log_retention_days   = var.log_retention_days
  db_bootstrap_command = var.db_bootstrap_command
  db_master_secret_arn = module.database.master_secret_arn

  common_env = [
    { name = "EC_ENVIRONMENT", value = var.environment },
    { name = "EC_RAW_BUCKET", value = module.raw_bucket.bucket_name },
    { name = "EC_SIGNING_KEY_ID", value = module.kms.signing_key_arn },
    { name = "EC_FINGERPRINT_KEY_ID", value = module.kms.fingerprint_key_arn },
    { name = "EC_HEARTBEAT_NAMESPACE", value = local.heartbeat_namespace },
    { name = "EC_HEARTBEAT_METRIC", value = local.heartbeat_metric },
    { name = "PGHOST", value = module.database.address },
    { name = "PGPORT", value = tostring(module.database.port) },
    { name = "PGDATABASE", value = module.database.db_name },
    { name = "PGSSLMODE", value = "verify-full" },
    { name = "PGSSLROOTCERT", value = "/app/certs/rds-global-bundle.pem" },
  ]

  components = {
    worker = {
      cpu               = var.worker_cpu
      memory            = var.worker_memory
      desired           = var.worker_desired_count
      subnet_ids        = module.network.worker_subnet_ids
      security_group_id = module.network.worker_sg_id
      role_arn          = module.identity.worker_role_arn
      command           = length(var.worker_command) > 0 ? var.worker_command : ["python", "-m", "app.worker"]
      schedule          = local.collect ? var.collection_schedule : null
      extra_env = concat(local.runtime_env, [
        { name = "PGUSER", value = var.db_worker_user },
        { name = "MS_CLIENT_ID", value = var.ms_client_id },
        { name = "MS_CERT_THUMBPRINT_SHA1", value = var.ms_cert_thumbprint_sha1 },
        { name = "MS_CERT_THUMBPRINT_SHA256", value = var.ms_cert_thumbprint_sha256 },
        { name = "EC_RAW_KEYS", value = jsonencode(module.kms.raw_key_arns) },
      ])
    }
    evaluator = {
      cpu               = var.evaluator_cpu
      memory            = var.evaluator_memory
      desired           = var.evaluator_desired_count
      subnet_ids        = module.network.evaluator_subnet_ids
      security_group_id = module.network.evaluator_sg_id
      role_arn          = module.identity.evaluator_role_arn
      command           = length(var.evaluator_command) > 0 ? var.evaluator_command : ["python", "-m", "app.evaluator"]
      schedule          = local.collect ? var.evaluation_schedule : null
      extra_env         = concat(local.runtime_env, [{ name = "PGUSER", value = var.db_evaluator_user }])
    }
    # Portal: API + React app. Runs in the worker subnets (NAT for Cognito and Secrets
    # Manager, names limited by DNS Firewall), reached only through the internal ALB.
    portal = {
      cpu               = var.portal_cpu
      memory            = var.portal_memory
      desired           = local.image_tag == "unset" ? 0 : var.portal_desired_count
      subnet_ids        = module.network.worker_subnet_ids
      security_group_id = module.network.portal_sg_id
      role_arn          = module.identity.portal_role_arn
      command           = []
      target_group_arn  = module.portal.target_group_arn
      container_port    = 8000
      extra_env = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "AWS_REGION", value = var.region },
        { name = "PGUSER", value = "ec_portal" },
        { name = "DB_IAM_AUTH", value = "true" },
        { name = "AUTH_MODE", value = "cognito" },
        { name = "PUBLIC_URL", value = module.portal.public_url },
        { name = "COGNITO_DOMAIN", value = module.portal.cognito_domain_url },
        { name = "COGNITO_CLIENT_ID", value = module.portal.cognito_client_id },
        { name = "COGNITO_USER_POOL_ID", value = module.portal.cognito_user_pool_id },
        { name = "SOURCE_SECRET_PREFIX", value = "ec/${var.environment}/source/" },
        { name = "SECRETS_KMS_KEY_ID", value = module.kms.secrets_key_arn },
        { name = "MS_CLIENT_ID", value = var.ms_client_id },
      ]
    }
  }
}

module "liveness" {
  source         = "./modules/liveness"
  name_prefix    = local.name_prefix
  environment    = var.environment
  account_id     = local.account_id
  namespace      = local.heartbeat_namespace
  metric_name    = local.heartbeat_metric
  period_minutes = var.liveness_period_minutes
  grace_periods  = var.liveness_grace_periods
  alarm_enabled  = var.liveness_alarm_enabled
}

# The portal invites users (Members pages): create, look up, add to the aoc_viewer group,
# list. No delete, no password set, no MFA change; platform_admin stays Terraform-only.
resource "aws_iam_role_policy" "portal_directory" {
  name = "manage-portal-users"
  role = module.identity.portal_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cognito-idp:AdminCreateUser", "cognito-idp:AdminGetUser", "cognito-idp:AdminAddUserToGroup", "cognito-idp:ListUsers", "cognito-idp:ListUsersInGroup"]
      Resource = module.portal.user_pool_arn
    }]
  })
}
