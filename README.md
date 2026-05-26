# aws-infra

Terraform infrastructure for the [b2mash](https://binarymash.io) platform on AWS.

## Overview

Manages all AWS resources for the b2mash product suite: VPC, ECS Fargate (5 services), RDS PostgreSQL, ElastiCache Redis, ALB with host-based routing, ACM/Route 53, CloudWatch monitoring, and GitHub Actions OIDC authentication.

**Region**: `af-south-1` (Cape Town)

## Quick Start

```bash
# One-time: bootstrap state bucket (if not already created)
cd bootstrap && terraform init && terraform apply && cd ..

# Initialize
terraform init -backend-config="key=staging/terraform.tfstate"

# Plan
terraform plan -var-file=environments/staging.tfvars

# Apply (staging auto-applies on merge to main via GitHub Actions)
terraform apply -var-file=environments/staging.tfvars
```

## CI/CD

| Event | Action |
|-------|--------|
| PR to main | `terraform plan` posted as PR comment |
| Merge to main | `terraform apply` staging (auto) |
| Manual dispatch | `terraform apply` production (with approval gate) |

## Related Repos

- [keycloak-saas](https://github.com/rakheen-dama/keycloak-saas) — Keycloak identity provider (builds Docker image, deploys to ECS)
- [kazi](https://github.com/heykazi/kazi) — Kazi product (frontend, backend, gateway, portal)

See [CLAUDE.md](CLAUDE.md) for full architecture details.
