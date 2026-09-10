#!/usr/bin/env bash
# Spark 4.1 Connect server entrypoint for Azure Container Apps.
# Generates spark-defaults.conf from environment variables and starts the
# Connect server backed by Unity Catalog OSS and ADLS Gen2.

set -euo pipefail

UNITY_CATALOG_URI="${UNITY_CATALOG_URI:?UNITY_CATALOG_URI is required}"
AZURE_STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT_NAME:?AZURE_STORAGE_ACCOUNT_NAME is required}"
AZURE_STORAGE_CONTAINER_NAME="${AZURE_STORAGE_CONTAINER_NAME:-warehouse}"
AZURE_SP_CLIENT_ID="${AZURE_SP_CLIENT_ID:?AZURE_SP_CLIENT_ID is required}"
AZURE_SP_CLIENT_SECRET="${AZURE_SP_CLIENT_SECRET:?AZURE_SP_CLIENT_SECRET is required}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:?AZURE_TENANT_ID is required}"
SPARK_CONNECT_PORT="${SPARK_CONNECT_PORT:-15002}"

SPARK_CONF_DIR="${SPARK_CONF_DIR:-/opt/spark/conf}"
SPARK_CONF_FILE="${SPARK_CONF_DIR}/spark-defaults.conf"

mkdir -p "${SPARK_CONF_DIR}"

cat > "${SPARK_CONF_FILE}" <<EOF
# Spark 4.1 Connect server configuration — Azure profile
# Generated at runtime by spark-connect-azure-entrypoint.sh

spark.sql.extensions org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions,io.delta.sql.DeltaSparkSessionExtension

# Unity Catalog OSS (Delta primary write path)
spark.sql.catalog.unity io.unitycatalog.spark.UCSingleCatalog
spark.sql.catalog.unity.uri ${UNITY_CATALOG_URI}
spark.sql.catalog.unity.token not_used

# Default Spark catalog for Delta extension functions
spark.sql.catalog.spark_catalog org.apache.spark.sql.delta.catalog.DeltaCatalog

# Iceberg REST catalog (read-only via UC OSS)
spark.sql.catalog.iceberg org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.iceberg.catalog-impl org.apache.iceberg.rest.RESTCatalog
spark.sql.catalog.iceberg.uri ${UNITY_CATALOG_URI}/api/2.1/unity-catalog/iceberg
spark.sql.catalog.iceberg.warehouse abfs://${AZURE_STORAGE_CONTAINER_NAME}@${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/

# ABFS OAuth authentication (service principal)
spark.hadoop.fs.azure.account.auth.type.${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net OAuth
spark.hadoop.fs.azure.account.oauth.provider.type.${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider
spark.hadoop.fs.azure.account.oauth2.client.id.${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net ${AZURE_SP_CLIENT_ID}
spark.hadoop.fs.azure.account.oauth2.client.secret.${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net ${AZURE_SP_CLIENT_SECRET}
spark.hadoop.fs.azure.account.oauth2.client.endpoint.${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/token

# Warehouse defaults
spark.sql.warehouse.dir abfs://${AZURE_STORAGE_CONTAINER_NAME}@${AZURE_STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/warehouse/sdp
spark.sql.sources.default delta

# Extra JARs (Iceberg, Delta, UC, ABFS, etc.)
spark.driver.extraClassPath /opt/spark/jars-extra/*
spark.executor.extraClassPath /opt/spark/jars-extra/*
EOF

echo "[spark-connect-azure-entrypoint] wrote ${SPARK_CONF_FILE}"

# Wait for the Unity Catalog REST API to be reachable so the Connect server
# can resolve catalogs on startup.
echo "[spark-connect-azure-entrypoint] waiting for Unity Catalog at ${UNITY_CATALOG_URI}..."
for _ in $(seq 1 60); do
    if curl -fsS --connect-timeout 2 "${UNITY_CATALOG_URI}/api/2.1/unity-catalog/catalogs" >/dev/null 2>&1; then
        echo "[spark-connect-azure-entrypoint] Unity Catalog is reachable"
        break
    fi
    sleep 2
done

echo "[spark-connect-azure-entrypoint] starting Spark Connect server on port ${SPARK_CONNECT_PORT}"

exec /opt/spark/sbin/start-connect-server.sh \
    --master "local[*]" \
    --conf "spark.connect.grpc.binding.host=0.0.0.0" \
    --conf "spark.connect.grpc.binding.port=${SPARK_CONNECT_PORT}"
