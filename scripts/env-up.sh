#!/usr/bin/env bash
# Bring up the runtime layer. Repeatable: if a final RDS snapshot exists from a
# previous env-down, the database is restored from it (tenant schemas, Keycloak
# realm, and users survive the cycle); the consumed snapshot is then deleted so
# the next env-down can write a fresh one.
#
# Prerequisites: persistent layer applied, secrets populated, images seeded.
#
# Usage: bash scripts/env-up.sh [staging|production]
set -euo pipefail

ENV="${1:-staging}"
PROJECT="kazi"
SNAPSHOT_ID="${PROJECT}-${ENV}-postgres-final"
REGION="${AWS_REGION:-af-south-1}"

cd "$(dirname "$0")/.."

RESTORE_ARGS=()
if aws rds describe-db-snapshots --db-snapshot-identifier "$SNAPSHOT_ID" \
    --region "$REGION" --query 'DBSnapshots[0].Status' --output text 2>/dev/null | grep -q available; then
  echo ">>> Final snapshot ${SNAPSHOT_ID} found — restoring the database from it."
  RESTORE_ARGS=(-var "rds_restore_snapshot_identifier=${SNAPSHOT_ID}")
else
  echo ">>> No final snapshot found — provisioning a fresh database."
fi

terraform init -backend-config="key=${ENV}/terraform.tfstate" -input=false
# Explicit branch: "${RESTORE_ARGS[@]}" on an empty array is an unbound-variable
# error under macOS bash 3.2 with set -u.
if [ ${#RESTORE_ARGS[@]} -gt 0 ]; then
  terraform apply -var-file="environments/${ENV}.tfvars" "${RESTORE_ARGS[@]}"
else
  terraform apply -var-file="environments/${ENV}.tfvars"
fi

if [ ${#RESTORE_ARGS[@]} -gt 0 ]; then
  echo ">>> Waiting for the restored database to become available..."
  aws rds wait db-instance-available \
    --db-instance-identifier "${PROJECT}-${ENV}-postgres" --region "$REGION"
  echo ">>> Deleting the consumed final snapshot (next env-down recreates it)."
  aws rds delete-db-snapshot --db-snapshot-identifier "$SNAPSHOT_ID" --region "$REGION" > /dev/null
fi

echo ""
echo "Runtime layer is up. ECS services pull the existing ECR images for ${ENV}"
echo "already in ECR — no rebuild needed. Useful outputs:"
terraform output mailpit_url 2>/dev/null || true
terraform output bastion_instance_id 2>/dev/null || true
