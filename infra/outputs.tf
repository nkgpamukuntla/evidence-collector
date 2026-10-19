output "raw_bucket" { value = module.raw_bucket.bucket_name }
output "signing_key_arn" { value = module.kms.signing_key_arn }
output "fingerprint_key_arn" { value = module.kms.fingerprint_key_arn }
output "secrets_key_arn" { value = module.kms.secrets_key_arn }
output "raw_key_arns" { value = module.kms.raw_key_arns }

output "worker_role_arn" { value = module.identity.worker_role_arn }
output "evaluator_role_arn" { value = module.identity.evaluator_role_arn }
output "terminator_role_arn" { value = module.identity.terminator_role_arn }

output "vpc_id" { value = module.network.vpc_id }
output "worker_subnet_ids" { value = module.network.worker_subnet_ids }
output "db_bootstrap_sg_id" { value = module.network.db_bootstrap_sg_id }
output "nat_public_ips" { value = module.network.nat_public_ips }

output "db_endpoint" { value = module.database.address }
output "ecr_repository_url" { value = module.compute.ecr_repository_url }
output "ecs_cluster_name" { value = module.compute.cluster_name }
output "db_bootstrap_task_family" { value = module.compute.db_bootstrap_task_family }
output "liveness_topic_arn" { value = module.liveness.topic_arn }

output "portal_url" { value = module.portal.public_url }
output "cognito_user_pool_id" { value = module.portal.cognito_user_pool_id }
output "build_project" { value = module.build.project_name }
