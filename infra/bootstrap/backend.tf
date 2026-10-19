# Rename to backend.tf AFTER the first apply, then:
#   terraform init -migrate-state -backend-config=../envs/<env>.backend.hcl -backend-config="key=bootstrap/terraform.tfstate"
terraform {
  backend "s3" {}
}
