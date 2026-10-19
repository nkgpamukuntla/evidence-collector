# ECS on Fargate, ARM64 only (R8). One image, two services + a one-off db-bootstrap task.
# Services start at desired_count 0 until the process entry point exists (R10).
resource "aws_ecr_repository" "collector" {
  name                 = "${var.name_prefix}-collector"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" } # KMS here would need CreateGrant (R4)
}

resource "aws_ecr_lifecycle_policy" "collector" {
  repository = aws_ecr_repository.collector.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last ${var.ecr_keep_images} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.ecr_keep_images }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled" # cost
  }
}

resource "aws_cloudwatch_log_group" "component" {
  for_each          = toset(concat(keys(var.components), ["db-bootstrap"]))
  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
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
  name               = "${var.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  image = "${aws_ecr_repository.collector.repository_url}:${var.image_tag}"

  # Root filesystem is read-only; /tmp is a task-scoped scratch volume.
  tmp_volume = { name = "tmp" }
  tmp_mount  = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]

  log_config = { for c in concat(keys(var.components), ["db-bootstrap"]) : c => {
    logDriver = "awslogs"
    options = {
      "awslogs-group"         = aws_cloudwatch_log_group.component[c].name
      "awslogs-region"        = var.region
      "awslogs-stream-prefix" = c
    }
  } }
}

resource "aws_ecs_task_definition" "component" {
  for_each                 = var.components
  family                   = "${var.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = each.value.role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  volume { name = local.tmp_volume.name }

  container_definitions = jsonencode([merge({
    name                   = each.key
    image                  = local.image
    essential              = true
    readonlyRootFilesystem = true
    mountPoints            = local.tmp_mount
    environment            = concat(var.common_env, each.value.extra_env, [{ name = "EC_COMPONENT", value = each.key }])
    logConfiguration       = local.log_config[each.key]
    },
    length(each.value.command) > 0 ? { command = each.value.command } : {},
    each.value.container_port == null ? {} : { portMappings = [{ containerPort = each.value.container_port, protocol = "tcp" }] },
  )])
}

resource "aws_ecs_service" "component" {
  for_each        = var.components
  name            = "${var.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.component[each.key].arn
  desired_count   = each.value.desired
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = each.value.subnet_ids
    security_groups  = [each.value.security_group_id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = each.value.target_group_arn == null ? [] : [each.value]
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = each.key
      container_port   = load_balancer.value.container_port
    }
  }

  health_check_grace_period_seconds = each.value.target_group_arn == null ? null : 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

# ---------- one-off db-bootstrap task (migrations + CONNECT grants) ----------
# Reads the RDS-managed master secret at run time, so DB credentials never touch state (R5).
resource "aws_iam_role" "db_bootstrap_execution" {
  name               = "${var.name_prefix}-db-bootstrap-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "db_bootstrap_execution" {
  role       = aws_iam_role.db_bootstrap_execution.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "db_bootstrap_secret" {
  name = "read-master-secret"
  role = aws_iam_role.db_bootstrap_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.db_master_secret_arn
    }]
  })
}

resource "aws_ecs_task_definition" "db_bootstrap" {
  family                   = "${var.name_prefix}-db-bootstrap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.db_bootstrap_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  volume { name = local.tmp_volume.name }

  container_definitions = jsonencode([{
    name                   = "db-bootstrap"
    image                  = local.image
    essential              = true
    readonlyRootFilesystem = true
    mountPoints            = local.tmp_mount
    command                = var.db_bootstrap_command
    environment            = concat(var.common_env, [{ name = "EC_COMPONENT", value = "db-bootstrap" }])
    secrets = [
      { name = "PGUSER", valueFrom = "${var.db_master_secret_arn}:username::" },
      { name = "PGPASSWORD", valueFrom = "${var.db_master_secret_arn}:password::" },
    ]
    logConfiguration = local.log_config["db-bootstrap"]
  }])
}

# ---------- scheduled runs (EventBridge Scheduler -> ECS RunTask) ----------
# The worker and evaluator run as one-off tasks on a schedule: no idle containers to pay for.
locals {
  scheduled = { for k, v in var.components : k => v if v.schedule != null }
}

resource "aws_iam_role" "scheduler" {
  count = length(local.scheduled) > 0 ? 1 : 0
  name  = "${var.name_prefix}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "scheduler" {
  count = length(local.scheduled) > 0 ? 1 : 0
  name  = "run-scheduled-tasks"
  role  = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "ecs:RunTask"
        Resource  = [for k, _ in local.scheduled : "${aws_ecs_task_definition.component[k].arn_without_revision}:*"]
        Condition = { ArnEquals = { "ecs:cluster" = aws_ecs_cluster.main.arn } }
      },
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = concat([aws_iam_role.task_execution.arn], [for k, v in local.scheduled : v.role_arn])
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
    ]
  })
}

resource "aws_scheduler_schedule" "component" {
  for_each                     = local.scheduled
  name                         = "${var.name_prefix}-${each.key}"
  schedule_expression          = each.value.schedule
  schedule_expression_timezone = "UTC"
  flexible_time_window { mode = "OFF" }

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler[0].arn
    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.component[each.key].arn
      launch_type         = "FARGATE"
      network_configuration {
        subnets          = each.value.subnet_ids
        security_groups  = [each.value.security_group_id]
        assign_public_ip = false
      }
    }
    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}
