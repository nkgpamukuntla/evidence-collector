# All security groups live here so their cross-references stay inside one module.
# New security groups start with no egress (Terraform removes AWS's default allow-all).

# ---------- evaluator: S3, KMS, Postgres (R6) + ECR/Logs endpoints so a task can start ----------
resource "aws_security_group" "evaluator" {
  name        = "${var.name_prefix}-evaluator"
  description = "Evaluator: egress to S3, KMS and Postgres only (R6), plus ECR/Logs endpoints"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "evaluator_s3" {
  security_group_id = aws_security_group.evaluator.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "evaluator_endpoint" {
  for_each                     = toset(["ecr.api", "ecr.dkr", "logs", "kms"])
  security_group_id            = aws_security_group.evaluator.id
  referenced_security_group_id = aws_security_group.endpoint[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "evaluator_db" {
  security_group_id            = aws_security_group.evaluator.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# ---------- worker: HTTPS out (names restricted by DNS Firewall), Postgres ----------
resource "aws_security_group" "worker" {
  name        = "${var.name_prefix}-worker"
  description = "Worker: HTTPS out (names restricted by DNS Firewall), Postgres to RDS"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "worker_https" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "worker_db" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# ---------- db-bootstrap: one-off migration task, runs in the worker subnets ----------
# HTTPS anywhere because it pulls its image and the master secret through NAT/endpoints.
resource "aws_security_group" "db_bootstrap" {
  name        = "${var.name_prefix}-db-bootstrap"
  description = "One-off migration task (runs in worker subnets)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "db_bootstrap_https" {
  security_group_id = aws_security_group.db_bootstrap.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "db_bootstrap_db" {
  security_group_id            = aws_security_group.db_bootstrap.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# ---------- db: Postgres from the three callers only ----------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db"
  description = "Postgres from worker, evaluator and db-bootstrap only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from" {
  for_each = {
    worker       = aws_security_group.worker.id
    evaluator    = aws_security_group.evaluator.id
    db_bootstrap = aws_security_group.db_bootstrap.id
    portal       = aws_security_group.portal.id
  }
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# ---------- portal: internal ALB -> portal tasks ----------
# The ALB is internal; CloudFront reaches it through a VPC origin, whose ENIs sit inside
# this VPC, so ingress is from the VPC range only. Nothing on the internet can reach it.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-portal-alb"
  description = "Internal ALB for the portal (CloudFront VPC origin)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_portal" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.portal.id
  ip_protocol                  = "tcp"
  from_port                    = var.portal_port
  to_port                      = var.portal_port
}

# Portal tasks run in the worker subnets: HTTPS out (Cognito, Secrets Manager; names
# restricted by DNS Firewall) and Postgres.
resource "aws_security_group" "portal" {
  name        = "${var.name_prefix}-portal"
  description = "Portal tasks: from the ALB only; HTTPS out, Postgres"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "portal_from_alb" {
  security_group_id            = aws_security_group.portal.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.portal_port
  to_port                      = var.portal_port
}

resource "aws_vpc_security_group_egress_rule" "portal_https" {
  security_group_id = aws_security_group.portal.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "portal_db" {
  security_group_id            = aws_security_group.portal.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
