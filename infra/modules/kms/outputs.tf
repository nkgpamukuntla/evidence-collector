output "raw_key_arns" { value = { for t, k in aws_kms_key.raw : t => k.arn } }
output "signing_key_arn" { value = aws_kms_key.signing.arn }
output "signing_key_id" { value = aws_kms_key.signing.key_id }
output "fingerprint_key_arn" { value = aws_kms_key.fingerprint.arn }
output "secrets_key_arn" { value = aws_kms_key.secrets.arn }
