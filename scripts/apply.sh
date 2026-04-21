#!/usr/bin/env bash
set -euo pipefail

PLANFILE="${1:-tfplan}"
ENVIRONMENT="${2:-prod}"

cd "$(dirname "$0")/.."

if [[ ! -f "${PLANFILE}" ]]; then
  echo "Plan file not found: ${PLANFILE}"
  exit 1
fi

read -r -p "Apply ${PLANFILE}? Type yes: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

terraform apply "${PLANFILE}"
terraform output
