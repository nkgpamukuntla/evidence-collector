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
      stack       = "infra"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}
