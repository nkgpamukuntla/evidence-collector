bucket       = "ec-dev-tfstate-REPLACE_ACCOUNT_ID"
key          = "infra/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
kms_key_id   = "REPLACE_STATE_KMS_KEY_ARN"
use_lockfile = true
