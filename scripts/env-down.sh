#!/usr/bin/env bash
# Tear down the runtime layer (VPC, ALB, ECS, RDS, Redis, NAT, bastion, DNS
# records). The persistent layer (ECR images, secrets, S3, OIDC) is untouched —
# idle cost drops to ~$10/mo. RDS writes a final snapshot that the next
# env-up.sh restores from.
#
# Usage: bash scripts/env-down.sh [staging|production]
set -euo pipefail

ENV="${1:-staging}"
PROJECT="kazi"
SNAPSHOT_ID="${PROJECT}-${ENV}-postgres-final"
REGION="${AWS_REGION:-af-south-1}"

cd "$(dirname "$0")/.."

# A leftover final snapshot (e.g. env-up was never run, or it failed before
# deleting it) would make the destroy fail with a name collision.
if aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" \
    --region "$REGION" --query 'DBSnapshots[0].Status' --output text 2>/dev/null | grep -q .; then
  echo "!!! A final snapshot named ${SNAPSHOT_ID} already exists."
  echo "!!! The destroy would fail trying to create another with the same name."
  read -r -p "Delete the OLD snapshot and continue (its data is superseded by the live DB)? [y/N] " ans
  [ "$ans" = "y" ] || { echo "Aborted."; exit 1; }
  aws rds delete-db-snapshot --db-snapshot-identifier "$SNAPSHOT_ID" --region "$REGION" > /dev/null
  aws rds wait db-snapshot-deleted --db-snapshot-identifier "$SNAPSHOT_ID" --region "$REGION"
fi

terraform init -backend-config="key=${ENV}/terraform.tfstate" -input=false
terraform destroy -var-file="environments/${ENV}.tfvars"

echo ""
echo "Runtime layer destroyed. Final DB snapshot: ${SNAPSHOT_ID}"
echo "Bring it back with: bash scripts/env-up.sh ${ENV}"
