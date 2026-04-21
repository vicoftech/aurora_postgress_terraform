#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

terraform fmt -recursive .

terraform init -backend=false -upgrade
terraform validate

echo "Validation OK."
