output "project_name" { value = aws_codebuild_project.app.name }
output "source_bucket" { value = aws_s3_bucket.source.id }
output "codesign_key_arn" { value = aws_kms_key.codesign.arn }
