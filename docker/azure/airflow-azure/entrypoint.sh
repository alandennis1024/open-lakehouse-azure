#!/usr/bin/env bash
# Airflow 3.1 entrypoint for Azure Container Apps.
# Initializes the Postgres DB, creates an admin user, sets up connections, and
# starts API server + scheduler + triggerer via supervisord.

set -euo pipefail

POSTGRES_HOST="${POSTGRES_HOST:?POSTGRES_HOST is required}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:?POSTGRES_USER is required}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
POSTGRES_DB="${POSTGRES_DB:-airflow}"

AIRFLOW_ADMIN_USER="${AIRFLOW_ADMIN_USER:-admin}"
AIRFLOW_ADMIN_PASSWORD="${AIRFLOW_ADMIN_PASSWORD:?AIRFLOW_ADMIN_PASSWORD is required}"

echo "[airflow-azure-entrypoint] waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
for _ in $(seq 1 60); do
    if PGPASSWORD="${POSTGRES_PASSWORD}" psql \
         -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
         -c 'SELECT 1' >/dev/null 2>&1; then
        echo "[airflow-azure-entrypoint] PostgreSQL is reachable"
        break
    fi
    sleep 2
done

echo "[airflow-azure-entrypoint] ensuring database ${POSTGRES_DB} exists"
PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -v ON_ERROR_STOP=1 -tc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" | grep -q 1 || \
PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
    -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE \"${POSTGRES_DB}\";"

export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
export AIRFLOW__CORE__LOAD_EXAMPLES="false"
export AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION="true"
export AIRFLOW__API__PORT="8085"
export AIRFLOW__API__AUTH_BACKENDS="airflow.api.auth.backend.basic_auth,airflow.api.auth.backend.session"
export AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK="true"

if [[ -z "${AIRFLOW__CORE__FERNET_KEY:-}" ]]; then
    echo "[airflow-azure-entrypoint] generating Fernet key"
    AIRFLOW__CORE__FERNET_KEY="$(python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
    export AIRFLOW__CORE__FERNET_KEY
fi

echo "[airflow-azure-entrypoint] migrating Airflow database"
airflow db migrate

echo "[airflow-azure-entrypoint] creating admin user ${AIRFLOW_ADMIN_USER} if missing"
airflow users list | grep -q "${AIRFLOW_ADMIN_USER}" || \
airflow users create \
    --username "${AIRFLOW_ADMIN_USER}" \
    --password "${AIRFLOW_ADMIN_PASSWORD}" \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email "${AIRFLOW_ADMIN_USER}@localhost"

echo "[airflow-azure-entrypoint] setting up Azure service connections"
setup-connections-azure.sh

echo "[airflow-azure-entrypoint] starting Airflow services"
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
