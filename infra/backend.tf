# Partial backend; values come from envs/<env>.backend.hcl (no secrets in it).
# If tools/terraform.sh does not already init with -backend=false, add it there.
terraform {
  backend "s3" {}
}
