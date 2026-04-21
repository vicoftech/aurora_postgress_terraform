#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-prod}"
AWS_REGION="${2:-us-west-2}"
AWS_PROFILE="${3:-}"

PROFILE_ARGS=()
if [[ -n "${AWS_PROFILE}" ]]; then
  PROFILE_ARGS=(--profile "${AWS_PROFILE}")
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text "${PROFILE_ARGS[@]}")
BUCKET_NAME="terraform-state-${ACCOUNT_ID}-aurora-${AWS_REGION}"
LOCKS_TABLE="terraform-locks"
STATE_KEY="aurora/${ENVIRONMENT}/terraform.tfstate"

echo "Initializing Terraform backend (S3 + DynamoDB locks)"
echo "  Bucket: ${BUCKET_NAME}"
echo "  Key:    ${STATE_KEY}"
echo "  Region: ${AWS_REGION}"

if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" "${PROFILE_ARGS[@]}" 2>/dev/null; then
  echo "Bucket missing. Run: ./scripts/bootstrap.sh ${AWS_REGION} ${AWS_PROFILE:-}"
  exit 1
fi

if ! aws dynamodb describe-table --table-name "${LOCKS_TABLE}" --region "${AWS_REGION}" "${PROFILE_ARGS[@]}" &>/dev/null; then
  echo "DynamoDB locks table missing. Run: ./scripts/bootstrap.sh ${AWS_REGION} ${AWS_PROFILE:-}"
  exit 1
fi

cd "$(dirname "$0")/.."

terraform init \
  -upgrade \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="key=${STATE_KEY}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${LOCKS_TABLE}" \
  -backend-config="encrypt=true" \
  -reconfigure

echo "Done. Next: terraform plan -var-file=environments/${ENVIRONMENT}/terraform.tfvars"
