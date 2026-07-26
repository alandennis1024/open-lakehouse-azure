#!/usr/bin/env bash
# MLflow entrypoint for Azure Container Apps.
# Waits for Azure PostgreSQL Flexible Server, then starts the MLflow tracking
# server with a WASB artifact root backed by Azure Blob Storage.

set -euo pipefail

POSTGRES_HOST="${POSTGRES_HOST:?POSTGRES_HOST is required}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:?POSTGRES_USER is required}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
POSTGRES_DB="${POSTGRES_DB:-mlflow}"

MLFLOW_ARTIFACTS_DESTINATION="${MLFLOW_ARTIFACTS_DESTINATION:?MLFLOW_ARTIFACTS_DESTINATION is required}"

echo "[mlflow-azure-entrypoint] waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
for _ in $(seq 1 30); do
    if PGPASSWORD="${POSTGRES_PASSWORD}" psql \
         -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
         -c 'SELECT 1' >/dev/null 2>&1; then
        echo "[mlflow-azure-entrypoint] PostgreSQL is reachable"
        break
    fi
    sleep 1
done

PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -v ON_ERROR_STOP=1 -tc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" | grep -q 1 || \
PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE \"${POSTGRES_DB}\";"

echo "[mlflow-azure-entrypoint] starting MLflow server with artifact root ${MLFLOW_ARTIFACTS_DESTINATION}"

exec mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}" \
    --default-artifact-root "${MLFLOW_ARTIFACTS_DESTINATION}"
