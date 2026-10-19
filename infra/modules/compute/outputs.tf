output "ecr_repository_url" { value = aws_ecr_repository.collector.repository_url }
output "ecr_repository_arn" { value = aws_ecr_repository.collector.arn }
output "cluster_name" { value = aws_ecs_cluster.main.name }
output "db_bootstrap_task_family" { value = aws_ecs_task_definition.db_bootstrap.family }
