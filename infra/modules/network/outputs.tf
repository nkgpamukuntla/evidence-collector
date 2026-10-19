output "vpc_id" { value = aws_vpc.main.id }
output "evaluator_subnet_ids" { value = aws_subnet.evaluator[*].id }
output "worker_subnet_ids" { value = aws_subnet.worker[*].id }
output "db_subnet_ids" { value = aws_subnet.db[*].id }

output "evaluator_sg_id" { value = aws_security_group.evaluator.id }
output "worker_sg_id" { value = aws_security_group.worker.id }
output "db_sg_id" { value = aws_security_group.db.id }
output "db_bootstrap_sg_id" { value = aws_security_group.db_bootstrap.id }
output "alb_sg_id" { value = aws_security_group.alb.id }
output "portal_sg_id" { value = aws_security_group.portal.id }

output "nat_public_ips" {
  description = "Source IPs Microsoft sees from the worker."
  value       = aws_eip.nat[*].public_ip
}
