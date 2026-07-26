# MLflow tracking server for Azure Container Apps.
#
# Extends the upstream full image with Azure Blob Storage support and the
# PostgreSQL client used by the entrypoint to wait for Azure Database for
# PostgreSQL Flexible Server.

FROM ghcr.io/mlflow/mlflow:v3.13.0-full

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && pip install --no-cache-dir azure-storage-blob psycopg2-binary \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/azure/mlflow-azure/entrypoint.sh /usr/local/bin/mlflow-azure-entrypoint.sh
RUN chmod +x /usr/local/bin/mlflow-azure-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/mlflow-azure-entrypoint.sh"]
