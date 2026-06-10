#!/usr/bin/env bash
# One-off: provision the persistent layer (ECR, secrets, S3, GitHub OIDC).
# Run after bootstrap/ (state bucket) and before anything else.
#
# Usage: bash scripts/persistent-up.sh [staging|production]
set -euo pipefail

ENV="${1:-staging}"
cd "$(dirname "$0")/../persistent"

terraform init -backend-config="key=${ENV}/persistent.tfstate" -input=false
terraform apply -var-file="environments/${ENV}.tfvars"

echo ""
echo "Persistent layer is up. Next steps:"
echo "  1. Populate the 19 secrets:    kazi/${ENV}/* (see deployment plan step B6)"
echo "  2. Set AWS_ROLE_ARN secret in the 3 repos to:"
terraform output -raw github_actions_role_arn
echo ""
echo "  3. Run the 'Seed Images' workflow in b2b-strawman (builds all 5 services -> ECR)"
echo "  4. Provision the runtime layer: bash scripts/env-up.sh ${ENV}"
