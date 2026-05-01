#!/usr/bin/env bash
# Reboot Aurora instances (readers by promotion tier, then writer) so cluster
# parameter group changes (e.g. maintenance_work_mem) take effect.
# Requires AWS credentials for the account that owns the cluster (see environments/<env>/terraform.tfvars).
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-asap_main}"

cd "$(dirname "$0")/.."
ENVIRONMENT="${1:-prod}"
VARFILE="environments/${ENVIRONMENT}/terraform.tfvars"

if [[ ! -f "$VARFILE" ]]; then
  echo "Missing $VARFILE" >&2
  exit 1
fi

REGION=$(grep -E '^[[:space:]]*aws_region[[:space:]]*=' "$VARFILE" | head -1 | cut -d'"' -f2)
CLUSTER=$(grep -E '^[[:space:]]*aurora_cluster_name[[:space:]]*=' "$VARFILE" | head -1 | cut -d'"' -f2)

if [[ -z "${REGION}" || -z "${CLUSTER}" ]]; then
  echo "Could not parse aws_region or aurora_cluster_name from $VARFILE" >&2
  exit 1
fi

echo "AWS_PROFILE: ${AWS_PROFILE}"
echo "Region:      $REGION"
echo "Cluster:     $CLUSTER"
echo "Instances (reboot order: higher promotion_tier first, writer last):"

IDS=$(aws rds describe-db-instances --region "$REGION" \
  --filters "Name=db-cluster-id,Values=${CLUSTER}" \
  --query 'reverse(sort_by(DBInstances, &PromotionTier))[*].DBInstanceIdentifier' --output text)

if [[ -z "${IDS// /}" ]]; then
  echo "No instances found for cluster ${CLUSTER}. Check AWS_PROFILE / account." >&2
  exit 1
fi

for id in $IDS; do
  echo "Rebooting ${id} ..."
  aws rds reboot-db-instance --region "$REGION" --db-instance-identifier "$id"
  echo "Waiting until ${id} is available ..."
  aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$id"
done

echo "Done. Verify with: psql ... -c 'SHOW maintenance_work_mem;'"
