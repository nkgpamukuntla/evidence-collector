output "address" { value = aws_db_instance.main.address }
output "port" { value = aws_db_instance.main.port }
output "db_name" { value = aws_db_instance.main.db_name }
output "master_secret_arn" { value = aws_db_instance.main.master_user_secret[0].secret_arn }
output "identifier" { value = aws_db_instance.main.identifier }
