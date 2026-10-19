# ECS on Fargate, ARM64 only (R8). One image, two services + a one-off db-bootstrap task.
resource "aws_ecr_repository" "collector" {
  name                 = "${local.name_prefix}-collector"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" } # KMS here would need CreateGrant (R4)
}

resource "aws_ecr_lifecycle_policy" "collector" {
  repository = aws_ecr_repository.collector.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

locals {
  components = {
    worker = {
      cpu     = var.worker_cpu
      memory  = var.worker_memory
      desired = var.worker_desired_count
      subnets = aws_subnet.worker[*].id
      sg      = aws_security_group.worker.id
      role    = local.worker_role_arn
      command = var.worker_command
    }
    evaluator = {
      cpu     = var.evaluator_cpu
      memory  = var.evaluator_memory
      desired = var.evaluator_desired_count
      subnets = local.evaluator_subnet_ids
      sg      = local.evaluator_sg_id
      role    = local.evaluator_role_arn
      command = var.evaluator_command
    }
  }

  common_env = [
    { name = "EC_ENVIRONMENT", value = var.environment },
    { name = "EC_RAW_BUCKET", value = local.raw_bucket_name },
    { name = "PGHOST", value = aws_db_instance.main.address },
    { name = "PGPORT", value = tostring(aws_db_instance.main.port) },
    { name = "PGDATABASE", value = aws_db_instance.main.db_name },
    { name = "PGSSLMODE", value = "verify-full" },
  ]
}

resource "aws_cloudwatch_log_group" "component" {
  for_each          = toset(["worker", "evaluator", "db-bootstrap"])
  name              = "/ecs/${local.name_prefix}/${each.key}"
  retention_in_days = 30
}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "component" {
  for_each                 = local.components
  family                   = "${local.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = each.value.role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([merge({
    name                   = each.key
    image                  = "${aws_ecr_repository.collector.repository_url}:${local.image_tag}"
    essential              = true
    readonlyRootFilesystem = true
    environment            = concat(local.common_env, [{ name = "EC_COMPONENT", value = each.key }])
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.component[each.key].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = each.key
      }
    }
  }, length(each.value.command) > 0 ? { command = each.value.command } : {})])
}

resource "aws_ecs_service" "component" {
  for_each        = local.components
  name            = "${local.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.component[each.key].arn
  desired_count   = each.value.desired
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = each.value.subnets
    security_groups  = [each.value.sg]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

# ---------- one-off db-bootstrap task (migrations + CONNECT grants) ----------
# Keeps DB credentials out of Terraform state (R5): it reads the RDS-managed master secret at run time.
resource "aws_security_group" "db_bootstrap" {
  name        = "${local.name_prefix}-db-bootstrap"
  description = "One-off migration task"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "db_bootstrap_https" {
  security_group_id = aws_security_group.db_bootstrap.id
  cidr_ipv4         = var.vpc_cidr
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

resource "aws_iam_role" "db_bootstrap_execution" {
  name               = "${local.name_prefix}-db-bootstrap-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "db_bootstrap_execution" {
  role       = aws_iam_role.db_bootstrap_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "db_bootstrap_secret" {
  name = "read-master-secret"
  role = aws_iam_role.db_bootstrap_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_ecs_task_definition" "db_bootstrap" {
  family                   = "${local.name_prefix}-db-bootstrap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.db_bootstrap_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name        = "db-bootstrap"
    image       = "${aws_ecr_repository.collector.repository_url}:${local.image_tag}"
    essential   = true
    command     = var.db_bootstrap_command
    environment = concat(local.common_env, [{ name = "EC_COMPONENT", value = "db-bootstrap" }])
    secrets = [
      { name = "PGUSER", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:username::" },
      { name = "PGPASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.component["db-bootstrap"].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "db-bootstrap"
      }
    }
  }])
}
