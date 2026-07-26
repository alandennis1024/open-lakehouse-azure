#!/usr/bin/env bash
# Unity Catalog OSS entrypoint for Azure Container Apps.
# Writes server.properties from environment variables and then execs the
# original container command.

set -euo pipefail

POSTGRES_HOST="${POSTGRES_HOST:?POSTGRES_HOST is required}"
POSTGRES_USER="${POSTGRES_USER:?POSTGRES_USER is required}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
POSTGRES_DB="${POSTGRES_DB:-iceberg_catalog}"

AZURE_STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT_NAME:?AZURE_STORAGE_ACCOUNT_NAME is required}"
AZURE_SP_CLIENT_ID="${AZURE_SP_CLIENT_ID:?AZURE_SP_CLIENT_ID is required}"
AZURE_SP_CLIENT_SECRET="${AZURE_SP_CLIENT_SECRET:?AZURE_SP_CLIENT_SECRET is required}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:?AZURE_TENANT_ID is required}"

SERVER_PROPS_DIR="/home/unitycatalog/etc/conf"
SERVER_PROPS_FILE="${SERVER_PROPS_DIR}/server.properties"

mkdir -p "${SERVER_PROPS_DIR}"

cat > "${SERVER_PROPS_FILE}" <<EOF
server.env=dev
server.port=8080
server.authorization=disable

# PostgreSQL backend (Azure Database for PostgreSQL Flexible Server)
hibernate.connection.driver_class=org.postgresql.Driver
hibernate.connection.url=jdbc:postgresql://${POSTGRES_HOST}:5432/${POSTGRES_DB}
hibernate.connection.username=${POSTGRES_USER}
hibernate.connection.password=${POSTGRES_PASSWORD}
hibernate.hbm2ddl.auto=update
hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect

# ADLS Gen2 / Azure Storage configuration
adls.storageAccountName.0=${AZURE_STORAGE_ACCOUNT_NAME}
adls.tenantId.0=${AZURE_TENANT_ID}
adls.clientId.0=${AZURE_SP_CLIENT_ID}
adls.clientSecret.0=${AZURE_SP_CLIENT_SECRET}
EOF

echo "[unitycatalog-azure-entrypoint] wrote ${SERVER_PROPS_FILE}"

exec "$@"
