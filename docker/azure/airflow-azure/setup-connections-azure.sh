#!/usr/bin/env bash
# Set up Airflow connections for the Azure deployment profile.
# Run inside the Airflow container after the database is initialized.

set -e

echo "Setting up Airflow connections for Azure..."

# Kafka / Event Hubs
airflow connections delete kafka_default 2>/dev/null || true
airflow connections add kafka_default \
    --conn-type kafka \
    --conn-extra "{\"bootstrap.servers\": \"${KAFKA_BOOTSTRAP_SERVERS:?KAFKA_BOOTSTRAP_SERVERS is required}\", \"group.id\": \"airflow-consumer\", \"security.protocol\": \"${KAFKA_SECURITY_PROTOCOL:-SASL_SSL}\"}"
echo "✓ Kafka connection configured (kafka_default)"

# Spark 4.1 Connect endpoint
airflow connections delete spark_azure 2>/dev/null || true
airflow connections add spark_azure \
    --conn-type spark \
    --conn-host "${SPARK_CONNECT_URL:?SPARK_CONNECT_URL is required}" \
    --conn-extra '{"deploy_mode": "client"}'
echo "✓ Spark Connect connection configured (spark_azure)"

# PostgreSQL
airflow connections delete postgres_default 2>/dev/null || true
airflow connections add postgres_default \
    --conn-type postgres \
    --conn-host "${POSTGRES_HOST:?POSTGRES_HOST is required}" \
    --conn-port "${POSTGRES_PORT:-5432}" \
    --conn-login "${POSTGRES_USER:?POSTGRES_USER is required}" \
    --conn-password "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}" \
    --conn-schema "${POSTGRES_DB:-airflow}"
echo "✓ PostgreSQL connection configured (postgres_default)"

# Unity Catalog REST endpoint
airflow connections delete unity_catalog 2>/dev/null || true
airflow connections add unity_catalog \
    --conn-type http \
    --conn-host "${UNITY_CATALOG_URL:?UNITY_CATALOG_URL is required}" \
    --conn-schema https
echo "✓ Unity Catalog connection configured (unity_catalog)"

# MLflow tracking endpoint
airflow connections delete mlflow 2>/dev/null || true
airflow connections add mlflow \
    --conn-type http \
    --conn-host "${MLFLOW_TRACKING_URI:?MLFLOW_TRACKING_URI is required}" \
    --conn-schema https
echo "✓ MLflow connection configured (mlflow)"

# Default variables
airflow variables set spark_version "4.1"
airflow variables set kafka_bootstrap_servers "${KAFKA_BOOTSTRAP_SERVERS}"
airflow variables set uc_endpoint "${UNITY_CATALOG_URL}/api/2.1/unity-catalog/iceberg"
echo "✓ Variables configured"

echo ""
echo "Airflow Azure connections setup complete."
