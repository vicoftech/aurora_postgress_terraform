#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${1:-us-west-2}"
AWS_PROFILE="${2:-}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text ${AWS_PROFILE:+--profile "$AWS_PROFILE"})
BUCKET_NAME="terraform-state-${ACCOUNT_ID}-aurora-${AWS_REGION}"
LOCKS_TABLE="terraform-locks"

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"
echo "Bucket: ${BUCKET_NAME}"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" ${AWS_PROFILE:+--profile "$AWS_PROFILE"} 2>/dev/null; then
  echo "S3 bucket already exists."
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    ${AWS_PROFILE:+--profile "$AWS_PROFILE"} \
    --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled \
    --region "${AWS_REGION}" \
    ${AWS_PROFILE:+--profile "$AWS_PROFILE"}
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --region "${AWS_REGION}" \
    ${AWS_PROFILE:+--profile "$AWS_PROFILE"}
  echo "Created S3 bucket ${BUCKET_NAME}"
fi

if aws dynamodb describe-table --table-name "${LOCKS_TABLE}" --region "${AWS_REGION}" ${AWS_PROFILE:+--profile "$AWS_PROFILE"} &>/dev/null; then
  echo "DynamoDB table already exists."
else
  aws dynamodb create-table \
    --table-name "${LOCKS_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" \
    ${AWS_PROFILE:+--profile "$AWS_PROFILE"}
  echo "Waiting for table to be active..."
  aws dynamodb wait table-exists --table-name "${LOCKS_TABLE}" --region "${AWS_REGION}" ${AWS_PROFILE:+--profile "$AWS_PROFILE"}
  echo "Created DynamoDB table ${LOCKS_TABLE}"
fi

echo "Bootstrap complete. Create a KMS key for RDS (see guide) and set kms_key_id in terraform.tfvars."
