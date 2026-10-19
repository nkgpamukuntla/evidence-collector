# RDS for PostgreSQL 16 (R9) in local-only subnets.
# Encryption: kms_key_arn = null uses the AWS-managed aws/rds key (Option B), because a
# customer key would need kms:CreateGrant, which R4 gives to nobody. Option A needs Tim.
# Credentials: the master password lives in Secrets Manager (RDS-managed), never in
# state (R5). Runtime roles log in with IAM auth tokens, so there is no app password at all.
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "pg16" {
  name   = "${var.name_prefix}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "main" {
  identifier                          = "${var.name_prefix}-pg"
  engine                              = "postgres"
  engine_version                      = var.engine_version
  auto_minor_version_upgrade          = false # version moves are a decision with a test run (R9)
  instance_class                      = var.instance_class
  allocated_storage                   = var.allocated_storage
  storage_type                        = "gp3"
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  db_name                             = "evidence"
  username                            = "ec_admin"
  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  multi_az                            = var.multi_az
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [var.security_group_id]
  parameter_group_name                = aws_db_parameter_group.pg16.name
  publicly_accessible                 = false
  performance_insights_enabled        = false # cost; enable in prod if needed
  monitoring_interval                 = 0
  backup_retention_period             = var.backup_retention_days
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = !var.deletion_protection
  final_snapshot_identifier           = "${var.name_prefix}-pg-final"
  copy_tags_to_snapshot               = true
}

# rds-db:connect for each runtime role -> its own Postgres user (created by the migrations
# with GRANT rds_iam). CONNECT on the database is granted by the db-bootstrap task.
resource "aws_iam_role_policy" "db_connect" {
  for_each = var.iam_db_users
  name     = "rds-iam-connect"
  role     = each.key
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:${var.partition}:rds-db:${var.region}:${var.account_id}:dbuser:${aws_db_instance.main.resource_id}/${each.value}"
    }]
  })
}
