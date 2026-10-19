# Evidence Collector – AWS hosting pack

Drop-in files for timhill220/evidence-collector. Not yet validated against the repo:
names in `infra/hosting_wiring.tf` are guesses until wired.

## Files
| Path | Purpose | PR |
|---|---|---|
| infra/bootstrap/* | State bucket + key, CloudTrail, KMS-change alerts, GitHub OIDC apply role (per account) | 1 |
| infra/backend.tf, infra/envs/*.backend.hcl | Remote state for infra/ | 1 |
| infra/hosting_wiring.tf | Single place mapping to existing network.tf / iam.tf / s3.tf | 2 |
| infra/hosting_variables.tf, envs/*.tfvars.example | New inputs | 2 |
| infra/hosting_worker_network.tf | IGW, NAT, worker subnets/route tables, worker SG, DNS Firewall | 2 |
| infra/hosting_endpoints.tf | 6 interface endpoints, per-endpoint SGs, evaluator egress | 3 |
| infra/hosting_database.tf | RDS PG16, db subnets, SG, force_ssl | 4 |
| infra/hosting_compute.tf | ECR, ECS cluster, task defs (ARM64), services, db-bootstrap task | 5 |
| Dockerfile, .dockerignore | linux/arm64 image | 5 |
| .github/workflows/* | infra-dev, infra-prod, app-image (ARM tests) | 6 |
| .github/CODEOWNERS, pull_request_template.md | Review rules | 1 |

## Wire-up checklist (before `tools/terraform.sh check`)
1. Point every local in hosting_wiring.tf at the real resource names.
2. Confirm new subnet netnums don't overlap network.tf's.
3. worker/evaluator role trust policies allow ecs-tasks.amazonaws.com.
4. Add the ECR layer bucket statement to the S3 gateway endpoint policy (network.tf).
5. Check the Python "no route off the VPC" test scopes to evaluator subnets only;
   the worker route tables now have a NAT default route by design (R6).
6. Check whether the evaluator SG already allows KMS/Postgres egress; don't duplicate.
7. tools/terraform.sh must init with -backend=false for the mocked tftest run.
8. Pin all GitHub Actions and base images by SHA/digest.
9. Do not create liveness alarm/paging until the entry point exists (R10).
