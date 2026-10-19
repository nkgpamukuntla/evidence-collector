output "worker_role_arn" { value = aws_iam_role.worker.arn }
output "worker_role_name" { value = aws_iam_role.worker.name }
output "evaluator_role_arn" { value = aws_iam_role.evaluator.arn }
output "evaluator_role_name" { value = aws_iam_role.evaluator.name }
output "terminator_role_arn" { value = aws_iam_role.terminator.arn }
output "portal_role_arn" { value = aws_iam_role.portal.arn }
output "portal_role_name" { value = aws_iam_role.portal.name }
