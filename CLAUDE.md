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
- ACM certificates + Route 53 DNS (*.binarymash.io)
- Secrets Manager (18 secrets)
- CloudWatch log groups + alarms + SNS alerts
- IAM roles (ECS task roles, GitHub Actions OIDC)
- ECS auto-scaling policies

## Commands

```bash
# Initialize with environment-specific state key
terraform init -backend-config="key=staging/terraform.tfstate"
terraform init -backend-config="key=production/terraform.tfstate"

# Plan and apply
terraform plan -var-file=environments/staging.tfvars
terraform apply -var-file=environments/staging.tfvars

# Format check
terraform fmt -check -recursive

# Validate
terraform validate
```

Always run `plan` before `apply`. Never apply without reviewing the plan output.

## Structure

```
aws-infra/
├── main.tf                    # Root module composing all child modules
├── variables.tf               # All input variables
├── outputs.tf                 # All output values
├── providers.tf               # AWS provider + S3 backend
├── versions.tf                # Terraform + provider version pins
├── bootstrap/                 # One-time: state bucket + lock table
├── modules/
│   ├── vpc/                   # VPC, subnets, NAT gateways
│   ├── security-groups/       # SG definitions and rules
│   ├── ecr/                   # Container registries
│   ├── data/                  # RDS PostgreSQL + ElastiCache Redis
│   ├── secrets/               # Secrets Manager entries
│   ├── iam/                   # Task roles, OIDC for GitHub Actions
│   ├── alb/                   # Public + internal ALB
│   ├── ecs/                   # ECS Fargate task defs + services
│   ├── dns/                   # Route 53 + ACM certificate
│   ├── monitoring/            # CloudWatch log groups + alarms
│   ├── autoscaling/           # ECS auto-scaling policies
│   └── s3/                    # S3 bucket for file storage
├── environments/
│   ├── staging.tfvars
│   └── production.tfvars
└── .github/workflows/
    └── terraform.yml          # Plan on PR, apply on merge
```

## Conventions

- **Naming**: `kazi-{env}-{resource}` for internal, `binarymash-` for customer-facing
- **State**: S3 remote (`binarymash-terraform-state`) with DynamoDB locking
- **Environments**: staging + production via separate tfvars
- **Secrets**: Placeholder values with `ignore_changes` lifecycle
- **No cross-environment references**

## Deploying Repos

| Repo | Deploys To | How |
|------|-----------|-----|
| keycloak-saas | ECS keycloak service | Pushes to `kazi/keycloak` ECR, updates ECS |
| kazi (b2b-strawman) | ECS frontend/backend/gateway/portal | Pushes to respective ECR repos, updates ECS |

Both repos use the GitHub Actions OIDC role provisioned by the IAM module.

## Domain Layout

| Subdomain | Service | Environment |
|-----------|---------|-------------|
| app.binarymash.io | Frontend | Production |
| auth.binarymash.io | Keycloak | Production |
| portal.binarymash.io | Portal | Production |
| staging-app.binarymash.io | Frontend | Staging |
| staging-auth.binarymash.io | Keycloak | Staging |
| staging-portal.binarymash.io | Portal | Staging |

## Version Constraints

- Terraform >= 1.9.0
- AWS provider >= 5.0
- Region: af-south-1 (Cape Town)
