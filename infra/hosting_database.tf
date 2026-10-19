# RDS for PostgreSQL 16 (R9) in its own subnets with no route off the VPC.
# Encryption key: var.db_kms_key_arn = null uses aws/rds (Option B, no R4 change).
# Option A (customer key + CreateGrant conditioned on kms:ViaService=rds + kms:GrantIsForAWSResource)
# needs Tim's sign-off before it is added to kms.tf.
resource "aws_subnet" "db" {
  count             = length(var.availability_zones)
  vpc_id            = local.vpc_id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, local.db_netnums[count.index])
  tags              = { Name = "${local.name_prefix}-db-${count.index}" }
}

resource "aws_route_table" "db" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-db-local-only" }
}

resource "aws_route_table_association" "db" {
  count          = length(aws_subnet.db)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db"
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db"
  description = "Postgres from worker, evaluator and db-bootstrap only"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from" {
  for_each = {
    worker       = aws_security_group.worker.id
    evaluator    = local.evaluator_sg_id
    db_bootstrap = aws_security_group.db_bootstrap.id
  }
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_parameter_group" "pg16" {
  name   = "${local.name_prefix}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "main" {
  identifier                  = "${local.name_prefix}-pg"
  engine                      = "postgres"
  engine_version              = var.db_engine_version
  auto_minor_version_upgrade  = false # version moves are a decision with a test run (R9)
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  kms_key_id                  = var.db_kms_key_arn
  db_name                     = "evidence"
  username                    = "ec_admin"
  manage_master_user_password = true # password lives in Secrets Manager, never in state (R5)
  multi_az                    = var.db_multi_az
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  parameter_group_name        = aws_db_parameter_group.pg16.name
  publicly_accessible         = false
  backup_retention_period     = var.environment == "prod" ? 35 : 7
  deletion_protection         = var.environment == "prod"
  skip_final_snapshot         = var.environment != "prod"
  final_snapshot_identifier   = "${local.name_prefix}-pg-final"
  copy_tags_to_snapshot       = true
}

output "db_endpoint" { value = aws_db_instance.main.address }
output "ecr_repository_url" { value = aws_ecr_repository.collector.repository_url }
output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
output "db_bootstrap_task_family" { value = aws_ecs_task_definition.db_bootstrap.family }
output "worker_subnet_ids" { value = aws_subnet.worker[*].id }
output "db_bootstrap_sg_id" { value = aws_security_group.db_bootstrap.id }
