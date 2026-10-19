## What
<!-- One section-5 piece per PR -->

## Rules touched (R1–R11)
<!-- Which rules this affects and how they still hold -->

## Checks
- [ ] `bash tools/terraform.sh check` green
- [ ] `terraform plan` attached (no unexpected destroys)
- [ ] No secret in tfvars, state or code (R5)
- [ ] No `kms:CreateGrant`, no root delegation in any key policy (R4)
