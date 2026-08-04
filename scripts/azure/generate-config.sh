#!/usr/bin/env bash
# Generate Azure deployment configuration files from terraform-azure outputs.
#
# Usage:
#   scripts/azure/generate-config.sh          # Generate .azure files only
#   scripts/azure/generate-config.sh --apply  # Generate and copy to active locations
#
# The script reads outputs from terraform-azure. Missing outputs can be supplied
# via environment variables (see collect_outputs below) for local testing or
# while the Terraform state is being populated.

set -euo pipefail

ROOT_DIR="${AZURE_GENERATE_CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TF_DIR="${ROOT_DIR}/terraform-azure"

ENV_AZURE="${ROOT_DIR}/.env.azure"
SPARK_AZURE="${ROOT_DIR}/config/spark/spark-defaults.conf.azure"
UC_AZURE="${ROOT_DIR}/config/unity-catalog/server.properties.azure"

# ---------------------------------------------------------------------------
# Terraform output helpers
# ---------------------------------------------------------------------------

tf_output() {
    local name="$1"
    terraform -chdir="${TF_DIR}" output -raw "${name}" 2>/dev/null
}

tf_output_optional() {
    local name="$1"
    local fallback="${2:-}"
    local value
    if value="$(tf_output "${name}")"; then
        printf '%s' "${value}"
    else
        printf '%s' "${fallback}"
    fi
}

# ---------------------------------------------------------------------------
# Collect Terraform outputs with environment overrides
# ---------------------------------------------------------------------------

collect_outputs() {
    RESOURCE_GROUP_NAME="$(tf_output_optional resource_group_name "${AZURE_RESOURCE_GROUP_NAME:-}")"
    STORAGE_ACCOUNT_NAME="$(tf_output_optional storage_account_name "${AZURE_STORAGE_ACCOUNT_NAME:-}")"
    STORAGE_BLOB_ENDPOINT="$(tf_output_optional storage_account_primary_blob_endpoint "${AZURE_STORAGE_BLOB_ENDPOINT:-}")"
    STORAGE_ACCESS_KEY="$(tf_output_optional storage_account_primary_access_key "${AZURE_STORAGE_ACCESS_KEY:-}")"
    STORAGE_CONTAINER_NAME="$(tf_output_optional storage_container_name "${AZURE_STORAGE_CONTAINER_NAME:-warehouse}")"
    MLFLOW_ARTIFACTS_CONTAINER="$(tf_output_optional mlflow_artifacts_container_name "${AZURE_MLFLOW_ARTIFACTS_CONTAINER_NAME:-mlflow-artifacts}")"
    POSTGRES_FQDN="$(tf_output_optional postgres_fqdn "${AZURE_POSTGRES_FQDN:-}")"
    POSTGRES_ADMIN_USERNAME="$(tf_output_optional postgres_admin_username "${AZURE_POSTGRES_ADMIN_USERNAME:-lakehouse}")"
    EVENTHUB_NAMESPACE="$(tf_output_optional eventhub_namespace_name "${AZURE_EVENTHUB_NAMESPACE:-}")"
    EVENTHUB_CONNECTION_STRING="$(tf_output_optional eventhub_namespace_connection_string "${AZURE_EVENTHUB_CONNECTION_STRING:-}")"
    EVENTHUB_NAME="$(tf_output_optional eventhub_name "${AZURE_EVENTHUB_NAME:-lakehouse-events}")"
    KEY_VAULT_NAME="$(tf_output_optional key_vault_name "${AZURE_KEY_VAULT_NAME:-}")"
    KEY_VAULT_URI="$(tf_output_optional key_vault_uri "${AZURE_KEY_VAULT_URI:-}")"
    ACR_LOGIN_SERVER="$(tf_output_optional acr_login_server "${AZURE_ACR_LOGIN_SERVER:-}")"
    UNITY_CATALOG_URL="$(tf_output_optional unity_catalog_url "${AZURE_UNITY_CATALOG_URL:-}")"
    MLFLOW_URL="$(tf_output_optional mlflow_url "${AZURE_MLFLOW_URL:-}")"
    SPARK_CONNECT_URL="$(tf_output_optional spark_connect_url "${AZURE_SPARK_CONNECT_URL:-}")"
    SPARK_CONNECT_FQDN="$(tf_output_optional spark_connect_fqdn "${AZURE_SPARK_CONNECT_FQDN:-}")"
    AIRFLOW_URL="$(tf_output_optional airflow_url "${AZURE_AIRFLOW_URL:-}")"

    SP_CLIENT_ID="${AZURE_SP_CLIENT_ID:-}"
    SP_CLIENT_SECRET="${AZURE_SP_CLIENT_SECRET:-}"
    SP_TENANT_ID="${AZURE_TENANT_ID:-}"
    POSTGRES_ADMIN_PASSWORD="${AZURE_POSTGRES_ADMIN_PASSWORD:-}"
    AIRFLOW_ADMIN_USER="${AZURE_AIRFLOW_ADMIN_USER:-airflow}"
    AIRFLOW_ADMIN_PASSWORD="${AZURE_AIRFLOW_ADMIN_PASSWORD:-}"
}

# ---------------------------------------------------------------------------
# Validate required values
# ---------------------------------------------------------------------------

validate_outputs() {
    local missing=()

    if [ -z "${RESOURCE_GROUP_NAME}" ]; then missing+=("resource_group_name (set AZURE_RESOURCE_GROUP_NAME)"); fi
    if [ -z "${STORAGE_ACCOUNT_NAME}" ]; then missing+=("storage_account_name (set AZURE_STORAGE_ACCOUNT_NAME)"); fi
    if [ -z "${STORAGE_CONTAINER_NAME}" ]; then missing+=("storage_container_name (set AZURE_STORAGE_CONTAINER_NAME)"); fi
    if [ -z "${POSTGRES_FQDN}" ]; then missing+=("postgres_fqdn (set AZURE_POSTGRES_FQDN)"); fi
    if [ -z "${POSTGRES_ADMIN_USERNAME}" ]; then missing+=("postgres_admin_username (set AZURE_POSTGRES_ADMIN_USERNAME)"); fi
    if [ -z "${POSTGRES_ADMIN_PASSWORD}" ]; then missing+=("AZURE_POSTGRES_ADMIN_PASSWORD"); fi
    if [ -z "${EVENTHUB_NAMESPACE}" ]; then missing+=("eventhub_namespace_name (set AZURE_EVENTHUB_NAMESPACE)"); fi
    if [ -z "${KEY_VAULT_NAME}" ]; then missing+=("key_vault_name (set AZURE_KEY_VAULT_NAME)"); fi
    if [ -z "${SP_CLIENT_ID}" ]; then missing+=("AZURE_SP_CLIENT_ID"); fi
    if [ -z "${SP_CLIENT_SECRET}" ]; then missing+=("AZURE_SP_CLIENT_SECRET"); fi
    if [ -z "${SP_TENANT_ID}" ]; then missing+=("AZURE_TENANT_ID"); fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing required values:" >&2
        for item in "${missing[@]}"; do
            echo "  - ${item}" >&2
        done
        echo "" >&2
        echo "Either apply terraform-azure first or set the corresponding environment variables." >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Generate .env.azure
# ---------------------------------------------------------------------------

generate_env_azure() {
    local generated_at
    generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    cat > "${ENV_AZURE}" <<EOF
# Azure deployment profile generated by scripts/azure/generate-config.sh
# Source: terraform-azure outputs + environment overrides
# Generated: ${generated_at}

LAKEHOUSE_PROFILE=azure

# -----------------------------------------------------------------------------
# PostgreSQL (Azure Database for PostgreSQL Flexible Server)
# -----------------------------------------------------------------------------
POSTGRES_HOST=${POSTGRES_FQDN}
POSTGRES_PORT=5432
POSTGRES_USER=${POSTGRES_ADMIN_USERNAME}
POSTGRES_PASSWORD=${POSTGRES_ADMIN_PASSWORD}
POSTGRES_DB=iceberg_catalog

# -----------------------------------------------------------------------------
# Azure Storage (ADLS Gen2)
# -----------------------------------------------------------------------------
AZURE_STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
AZURE_STORAGE_CONTAINER_NAME=${STORAGE_CONTAINER_NAME}
AZURE_STORAGE_BLOB_ENDPOINT=${STORAGE_BLOB_ENDPOINT}
AZURE_STORAGE_PRIMARY_ACCESS_KEY=${STORAGE_ACCESS_KEY}
AZURE_MLFLOW_ARTIFACTS_CONTAINER_NAME=${MLFLOW_ARTIFACTS_CONTAINER}

# -----------------------------------------------------------------------------
# Azure Event Hubs (Kafka-compatible endpoint)
# -----------------------------------------------------------------------------
AZURE_EVENTHUB_NAMESPACE=${EVENTHUB_NAMESPACE}
AZURE_EVENTHUB_NAME=${EVENTHUB_NAME}
AZURE_EVENTHUB_CONNECTION_STRING=${EVENTHUB_CONNECTION_STRING}
KAFKA_BOOTSTRAP_SERVERS=${EVENTHUB_NAMESPACE}.servicebus.windows.net:9093

# -----------------------------------------------------------------------------
# Azure Key Vault
# -----------------------------------------------------------------------------
AZURE_KEY_VAULT_NAME=${KEY_VAULT_NAME}
AZURE_KEY_VAULT_URI=${KEY_VAULT_URI}

# -----------------------------------------------------------------------------
# Azure Container Registry
# -----------------------------------------------------------------------------
AZURE_ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}

# -----------------------------------------------------------------------------
# Unity Catalog / MLflow / Spark Connect / Airflow endpoints (Azure Container Apps)
# -----------------------------------------------------------------------------
UNITY_CATALOG_URI=${UNITY_CATALOG_URL}
MLFLOW_TRACKING_URI=${MLFLOW_URL}
LAKEHOUSE_SPARK_MODE=connect
LAKEHOUSE_SPARK_REMOTE=${SPARK_CONNECT_URL}

AIRFLOW_UI_URL=${AIRFLOW_URL}
AIRFLOW_ADMIN_USER=${AIRFLOW_ADMIN_USER}
AIRFLOW_ADMIN_PASSWORD=${AIRFLOW_ADMIN_PASSWORD}

# -----------------------------------------------------------------------------
# Spark Connect FQDN (for clients that need the host only)
# -----------------------------------------------------------------------------
AZURE_SPARK_CONNECT_FQDN=${SPARK_CONNECT_FQDN}

# -----------------------------------------------------------------------------
# Azure Service Principal (for ADLS / ABFS OAuth)
# -----------------------------------------------------------------------------
AZURE_SP_CLIENT_ID=${SP_CLIENT_ID}
AZURE_SP_CLIENT_SECRET=${SP_CLIENT_SECRET}
AZURE_TENANT_ID=${SP_TENANT_ID}
EOF
}

# ---------------------------------------------------------------------------
# Generate config/spark/spark-defaults.conf.azure
# ---------------------------------------------------------------------------

generate_spark_azure() {
    local example="${ROOT_DIR}/config/spark/spark-defaults.conf.example"
    if [ ! -f "${example}" ]; then
        echo "Missing ${example}" >&2
        return 1
    fi

    # Read the example and remove local SeaweedFS / S3 credential lines so the
    # Azure overlay is the authoritative storage configuration.
    local base
    base="$(sed \
        -e '/^spark\.hadoop\.fs\.s3a\.endpoint/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.access\.key/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.secret\.key/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.path\.style\.access/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.impl/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.connection\.ssl\.enabled/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.multiobjectdelete\.enable/d' \
        -e '/^spark\.hadoop\.fs\.s3a\.directory\.marker\.retention/d' \
        -e '/^spark\.hadoop\.fs\.s3\.impl/d' \
        -e '/^spark\.hadoop\.fs\.AbstractFileSystem\.s3\.impl/d' \
        -e '/^spark\.sql\.warehouse\.dir/d' \
        -e '/^spark\.sql\.sources\.default/d' \
        -e '/^spark\.sql\.catalog\.unity\.uri/d' \
        -e '/^spark\.sql\.catalog\.iceberg\.uri/d' \
        -e '/^spark\.sql\.catalog\.iceberg\.warehouse/d' \
        -e '/^spark\.jars /d' \
        -e '/<storage-account>/d' \
        -e '/<client-id>/d' \
        -e '/<client-secret>/d' \
        -e '/<tenant-id>/d' \
        "${example}")"

    {
        printf '%s\n' "${base}"
        echo ""
        echo "# ============================================================================"
        echo "# Azure / ABFS overlay (generated by scripts/azure/generate-config.sh)"
        echo "# ============================================================================"
        echo "spark.sql.catalog.unity.uri               ${UNITY_CATALOG_URL:-http://localhost:8081}"
        echo "spark.sql.catalog.iceberg.uri             ${UNITY_CATALOG_URL:-http://localhost:8081}/api/2.1/unity-catalog/iceberg"
        echo "spark.sql.catalog.iceberg.warehouse       abfs://${STORAGE_CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/"
        echo ""
        echo "# ABFS OAuth (service principal)"
        echo "spark.hadoop.fs.azure.account.auth.type.${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net OAuth"
        echo "spark.hadoop.fs.azure.account.oauth.provider.type.${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider"
        echo "spark.hadoop.fs.azure.account.oauth2.client.id.${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net ${SP_CLIENT_ID}"
        echo "spark.hadoop.fs.azure.account.oauth2.client.secret.${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net ${SP_CLIENT_SECRET}"
        echo "spark.hadoop.fs.azure.account.oauth2.client.endpoint.${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net https://login.microsoftonline.com/${SP_TENANT_ID}/oauth2/token"
        echo ""
        echo "# Alternative: account key auth (uncomment and comment OAuth above to use)"
        echo "# spark.hadoop.fs.azure.account.key.${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net ${STORAGE_ACCESS_KEY}"
        echo ""
        echo "spark.sql.warehouse.dir                   abfs://${STORAGE_CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/warehouse/sdp"
        echo "spark.sql.sources.default                 delta"
        echo ""
        echo "# Required JARs: add hadoop-azure to the local set."
        echo "spark.jars  /opt/spark/jars-extra/iceberg-spark-runtime-4.0_2.13-1.10.0.jar,/opt/spark/jars-extra/delta-spark_2.13-4.2.0.jar,/opt/spark/jars-extra/delta-storage-4.2.0.jar,/opt/spark/jars-extra/unitycatalog-spark_2.13-0.3.0.jar,/opt/spark/jars-extra/unitycatalog-client-0.3.0.jar,/opt/spark/jars-extra/hadoop-azure-3.4.1.jar,/opt/spark/jars-extra/hadoop-azure-datalake-3.4.1.jar"
    } > "${SPARK_AZURE}"
}

# ---------------------------------------------------------------------------
# Generate config/unity-catalog/server.properties.azure
# ---------------------------------------------------------------------------

generate_uc_azure() {
    local example="${ROOT_DIR}/config/unity-catalog/server.properties.example"
    if [ ! -f "${example}" ]; then
        echo "Missing ${example}" >&2
        return 1
    fi

    local generated_at
    generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    {
        echo "# Unity Catalog OSS Server Configuration"
        echo "# Generated by scripts/azure/generate-config.sh from ${example}"
        echo "# Generated: ${generated_at}"
        echo "# Documentation: https://docs.unitycatalog.io/"
        echo ""
        echo "# Server settings"
        echo "server.env=dev"
        echo "server.port=8080"
        echo "server.authorization=disable"
        echo ""
        echo "# ============================================================================"
        echo "# ADLS Gen2 / Azure Storage overlay"
        echo "# ============================================================================"
        echo "adls.storageAccountName.0=${STORAGE_ACCOUNT_NAME}"
        echo "adls.tenantId.0=${SP_TENANT_ID}"
        echo "adls.clientId.0=${SP_CLIENT_ID}"
        echo "adls.clientSecret.0=${SP_CLIENT_SECRET}"
        echo ""
        echo "# ============================================================================"
        echo "# PostgreSQL backend (Azure Database for PostgreSQL Flexible Server)"
        echo "# ============================================================================"
        echo "hibernate.connection.driver_class=org.postgresql.Driver"
        echo "hibernate.connection.url=jdbc:postgresql://${POSTGRES_FQDN}:5432/${POSTGRES_DB:-iceberg_catalog}"
        echo "hibernate.connection.username=${POSTGRES_ADMIN_USERNAME}"
        echo "hibernate.connection.password=${POSTGRES_ADMIN_PASSWORD}"
        echo "hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect"
    } > "${UC_AZURE}"
}

# ---------------------------------------------------------------------------
# Apply generated files to active locations with confirmation
# ---------------------------------------------------------------------------

backup_and_copy() {
    local src="$1"
    local dest="$2"

    if [ -f "${dest}" ]; then
        local response
        read -r -p "Overwrite ${dest}? [y/N] " response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            echo "Skipping ${dest}"
            return 0
        fi
        cp "${dest}" "${dest}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    cp "${src}" "${dest}"
    echo "Applied ${src} -> ${dest}"
}

apply_generated_files() {
    backup_and_copy "${ENV_AZURE}" "${ROOT_DIR}/.env"
    backup_and_copy "${SPARK_AZURE}" "${ROOT_DIR}/config/spark/spark-defaults.conf"
    backup_and_copy "${UC_AZURE}" "${ROOT_DIR}/config/unity-catalog/server.properties"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local apply=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apply) apply=true; shift ;;
            -h|--help)
                echo "Usage: $(basename "$0") [--apply]"
                echo "  --apply  Copy generated .azure files to active locations (with prompts)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ ! -d "${TF_DIR}" ]; then
        echo "Terraform directory not found: ${TF_DIR}" >&2
        exit 1
    fi

    collect_outputs
    validate_outputs

    echo "Generating Azure profile files..."
    generate_env_azure
    generate_spark_azure
    generate_uc_azure

    echo ""
    echo "Generated:"
    echo "  ${ENV_AZURE}"
    echo "  ${SPARK_AZURE}"
    echo "  ${UC_AZURE}"

    if [ "${apply}" = true ]; then
        echo ""
        apply_generated_files
        echo ""
        echo "Active locations updated. Review backups (.backup.<timestamp>) before the next run."
    fi
}

main "$@"
