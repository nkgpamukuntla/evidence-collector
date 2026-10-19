# Separate root, applied once per AWS account by a human (local state first,
# then migrated into the bucket it creates). Pins match infra/.
terraform {
  required_version = "= 1.16.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.65.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project     = "evidence-collector"
      environment = var.environment
      managed_by  = "terraform"
      stack       = "bootstrap"
    }
  }
}
