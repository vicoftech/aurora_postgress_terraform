#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
READER_ENDPOINT=$(terraform output -raw cluster_reader_endpoint)
DATABASE_NAME=$(terraform output -raw database_name)
MASTER_USERNAME=$(terraform output -raw master_username)

echo "Writer:  ${CLUSTER_ENDPOINT}"
echo "Reader:  ${READER_ENDPOINT}"
echo "Database: ${DATABASE_NAME}"
echo ""
read -r -s -p "Database password: " DB_PASSWORD
echo ""

export PGPASSWORD="${DB_PASSWORD}"

psql -h "${CLUSTER_ENDPOINT}" -U "${MASTER_USERNAME}" -d "${DATABASE_NAME}" -c "SELECT version();"
psql -h "${READER_ENDPOINT}" -U "${MASTER_USERNAME}" -d "${DATABASE_NAME}" -c "SELECT version();" || true

unset PGPASSWORD

echo "Done."
