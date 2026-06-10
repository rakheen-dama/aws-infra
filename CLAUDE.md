# CLAUDE.md — aws-infra

Terraform IaC for deploying b2mash products to AWS.
Extracted from b2b-strawman/infra to serve as a shared infrastructure repo.

## What This Repo Manages

All AWS infrastructure for the b2mash platform:
- VPC, subnets, NAT gateways (af-south-1, 2 AZs)
- ALB (public HTTPS + internal HTTP) with host-based routing
- ECS Fargate cluster with 5 services (frontend, backend, gateway, portal, keycloak)
- RDS PostgreSQL 16 (schema-per-tenant multitenancy)
- ElastiCache Redis (gateway session storage)
- ECR repositories (one per service)
- ACM certificates + Route 53 DNS (*.heykazi.com)
- Secrets Manager (18 secrets)
- CloudWatch log groups + alarms + SNS alerts
- IAM roles (ECS task roles, GitHub Actions OIDC)
- ECS auto-scaling policies

## Commands

```bash
# Initialize with environment-specific state key
terraform init -backend-config="key=staging/terraform.tfstate"
terraform init -backend-config="key=production/terraform.tfstate"

# Plan and apply (runtime layer — root)
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/staging.tfvars

# Operator scripts (preferred)
bash scripts/persistent-up.sh staging   # one-off: ECR, secrets, S3, GitHub OIDC
bash scripts/env-up.sh staging          # bring runtime up (restores RDS final snapshot if present)
bash scripts/env-down.sh staging        # tear runtime down (~$10/mo idle: persistent layer only)

# Format check
terraform fmt -check -recursive

# Validate (both roots)
terraform validate && (cd persistent && terraform validate)

# DB access via the SSM bastion (requires session-manager-plugin)
aws ssm start-session --target $(terraform output -raw bastion_instance_id) \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<rds-endpoint>"],"portNumber":["5432"],"localPortNumber":["15432"]}'
# then connect your DB client to localhost:15432
```

Always run `plan` before `apply`. Never apply without reviewing the plan output.

## Two-Layer Structure

The infrastructure is split into two Terraform roots with separate state, so the
expensive runtime can be destroyed and recreated on demand while registry,
secrets, files, and CI identity persist:

| Layer | Root | State key | Contents | Idle cost |
|-------|------|-----------|----------|-----------|
| Persistent | `persistent/` | `<env>/persistent.tfstate` | ECR repos + images, Secrets Manager (19), S3 app bucket, GitHub OIDC + Actions role | ~$10/mo |
| Runtime | `.` | `<env>/terraform.tfstate` | VPC, ALB, ECS, RDS, Redis, DNS records, ACM, bastion, Mailpit, monitoring, autoscaling, ECS task roles | $0 when down |

The runtime layer consumes persistent resources via **data sources and naming
convention** (`kazi/<env>/<secret>`, `kazi/<svc>` ECR, `kazi-<env>` bucket) —
never remote state. ECR repos and the OIDC provider are **cross-environment
singletons** owned by the staging persistent layer (`manage_shared = true`).

### Operating model (three actions)

1. **One-off**: `bootstrap/` → `scripts/persistent-up.sh` → populate secrets → set
   `AWS_ROLE_ARN` in repos → run the `seed-images` workflow in b2b-strawman
   (pushes all 5 `:staging` images — no ECS involved).
2. **Runtime up/down**: `scripts/env-up.sh` / `scripts/env-down.sh` (or the
   `terraform.yml` workflow_dispatch: layer=runtime, action=apply/destroy).
   Down writes a final RDS snapshot (`kazi-<env>-postgres-final`); up restores
   from it — tenant schemas, Keycloak realm, and users survive cycles. ACM
   revalidates (~2–5 min); Redis sessions and Mailpit inboxes are lost.
3. **Code deploys**: `deploy-staging.yml` in b2b-strawman (changed services →
   ECR → new task def revision). Terraform ignores task_definition drift.

```
aws-infra/
├── main.tf / variables.tf / outputs.tf   # RUNTIME root
├── persistent-refs.tf         # data sources + conventions into persistent layer
├── persistent/                # PERSISTENT root (own state, own tfvars)
├── bootstrap/                 # One-time: state bucket + lock table
├── scripts/                   # persistent-up.sh, env-up.sh, env-down.sh
├── docs/iam/                  # deploy-user policies (kazi-infra IAM user)
├── modules/
│   ├── vpc/ security-groups/ data/ alb/ ecs/ dns/ monitoring/ autoscaling/ bastion/   # runtime
│   ├── ecr/ secrets/ s3/ github-oidc/                                                 # persistent
│   └── iam/                   # ECS task + execution roles (runtime)
├── environments/              # runtime tfvars (staging, production)
└── .github/workflows/
    └── terraform.yml          # PR: plan both layers · merge: apply both · dispatch: plan/apply/destroy per layer
```

## Conventions

- **Naming**: `kazi-{env}-{resource}` for internal resources, `heykazi.com` for customer-facing domains, `binarymash-` for shared platform resources (state bucket, lock table)
- **State**: S3 remote (`binarymash-terraform-state`) with DynamoDB locking; two keys per environment (persistent + runtime)
- **Environments**: staging + production via separate tfvars (runtime in `environments/`, persistent in `persistent/environments/`)
- **Secrets**: Placeholder values with `ignore_changes` lifecycle; populated manually once (persistent layer survives env-down)
- **No cross-environment references** (except the deliberate shared singletons: ECR repos, OIDC provider)

## Deploying Repos

| Repo | Deploys To | How |
|------|-----------|-----|
| keycloak-saas | ECS keycloak service | Pushes to `kazi/keycloak` ECR, updates ECS |
| kazi (b2b-strawman) | ECS frontend/backend/gateway/portal (+ keycloak image + seed-images) | Pushes to respective ECR repos, updates ECS |

All repos use the GitHub Actions OIDC role provisioned by `modules/github-oidc` (persistent layer). Its `AWS_ROLE_ARN` is a `persistent/` output.

## Domain Layout

| Subdomain | Service | Environment |
|-----------|---------|-------------|
| app.heykazi.com | Frontend | Production |
| auth.heykazi.com | Keycloak | Production |
| portal.heykazi.com | Portal | Production |
| staging-app.heykazi.com | Frontend | Staging |
| staging-auth.heykazi.com | Keycloak | Staging |
| staging-portal.heykazi.com | Portal | Staging |
| staging-mail.heykazi.com | Mailpit UI (email capture mode) | Staging |

## Email Modes

`email_mode` per environment: `"capture"` (staging) traps all outbound email in an
in-VPC Mailpit ECS service — unlimited addresses, UI + REST API at the mail
subdomain behind Mailpit basic auth (`mailpit-ui-auth` secret, `user:password`).
`"ses"` (production) sends real email via the SMTP_* settings.

Switching modes = `terraform apply` (backend task def gets new SMTP env) **plus**
re-running the Keycloak realm SMTP bootstrap step (keycloak-saas
`scripts/bootstrap-realm.sh`) with matching SMTP values — Keycloak stores SMTP in
realm config, not env vars. Mailpit messages don't survive task replacement.

## Version Constraints

- Terraform >= 1.9.0
- AWS provider >= 5.0
- Region: af-south-1 (Cape Town)
