# Evidence Collector

Measures a public entity's actual security controls (a county, a court) against versioned
control sets, through read-only access the entity grants, and keeps a per-entity evidence
record. Design and rules (R1–R11): [docs/handover/2026-09-29-hosting-package.html](docs/handover/2026-09-29-hosting-package.html).

Hosted in a dedicated AWS account (`dbiz-edr-solutions`, us-east-1), independent of PRISM.
Everything is Terraform (R2), deployed from a workstation; there are no CI pipelines.

## Layout

```
infra/
  bootstrap/            once per account: CloudTrail, KMS-change alerts, state bucket + key,
                        break-glass key-admin role (local state first, then migrated)
  main.tf               root stack: wires the modules for one environment
  envs/<env>.tfvars     local only (gitignored); copy from <env>.tfvars.example
  envs/<env>.backend.hcl
  envs/<env>.image      image tag the services run
  modules/
    identity/           worker, evaluator, terminator roles
    kms/                raw[tenant], signing (RSA-2048), fingerprint (HMAC-256), secrets
    raw-bucket/         Object Lock bucket, per-tenant key enforcement
    network/            VPC, evaluator/public/worker/db tiers, NAT, endpoints, SGs, DNS Firewall
    database/           RDS PostgreSQL 16.15, IAM auth, force_ssl
    compute/            ECR, ECS Fargate ARM64 services, db-bootstrap task
    liveness/           heartbeat topic + alarm (alarm off until R10 allows)
```

## Prerequisites (no admin rights needed)

- Terraform 1.16.3: `C:\Dbiz-Projects\AOC\tools\terraform-1.16.3\terraform.exe`
- AWS CLI v2 with the `edr-dev` SSO profile: `aws sso login --profile edr-dev`

## Deploy

```powershell
$env:AWS_PROFILE = "edr-dev"
$tf = "C:\Dbiz-Projects\AOC\tools\terraform-1.16.3\terraform.exe"

# 1. Bootstrap (once per account)
cd infra\bootstrap
& $tf init
& $tf plan -var-file=dev.tfvars -out=bootstrap.tfplan
& $tf apply bootstrap.tfplan
#    then move its state into the bucket it created (see backend.tf.example)

# 2. Environment
cd ..
& $tf init -backend-config=envs/dev.backend.hcl
& $tf plan -var-file=envs/dev.tfvars -out=dev.tfplan
& $tf apply dev.tfplan
```

Always apply a saved plan, and read it first.

## Cost (dev, idle)

| Item | Approx. per month |
|---|---|
| NAT gateway (1) | $33 + data |
| Interface endpoints (4 × 1 AZ) | $29 |
| RDS db.t4g.micro + 20 GB gp3 | $14 |
| KMS keys (3 + 1 per tenant, + state key) | $4+ |
| ECS services | $0 while desired_count = 0 |
| CloudWatch Logs (14-day retention), DNS Firewall, S3 | a few dollars |

Stop RDS when idle (`aws rds stop-db-instance`, auto-restarts after 7 days).
List prices recalled for us-east-1, not a quote.

## Open items

- Process entry point (none yet): services stay at 0 tasks and the liveness alarm stays off (R10).
- Database key: AWS-managed `aws/rds` (Option B); a customer key needs a decision on R4.
- Postgres runtime users (`ec_worker`, `ec_evaluator`) need `GRANT rds_iam` in the migrations.
- Worker must send the tenant key ARN in `x-amz-server-side-encryption-aws-kms-key-id`.
- Pin base images by digest in the Dockerfile.
- External deadman monitor and paging destination: not chosen.
