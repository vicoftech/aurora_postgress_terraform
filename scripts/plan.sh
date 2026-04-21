#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-prod}"
PLANFILE="tfplan-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"

cd "$(dirname "$0")/.."

terraform plan \
  -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
  -out="${PLANFILE}"

echo "Plan written to ${PLANFILE}"
