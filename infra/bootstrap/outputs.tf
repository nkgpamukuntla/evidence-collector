output "state_bucket" { value = aws_s3_bucket.state.id }
output "state_kms_key_arn" { value = aws_kms_key.state.arn }
output "key_admin_role_arn" { value = aws_iam_role.key_admin.arn }
output "security_alerts_topic_arn" { value = aws_sns_topic.security_alerts.arn }
output "account_id" { value = local.account_id }
