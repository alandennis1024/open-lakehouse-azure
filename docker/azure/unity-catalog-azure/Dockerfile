# Unity Catalog OSS server for Azure Container Apps.
#
# Extends the public image with an entrypoint that writes server.properties from
# environment variables so the container can be configured at runtime with
# Azure PostgreSQL and ADLS Gen2 settings.

FROM newfrontdocker/unitycatalog:v0.4.1

USER root

COPY docker/azure/unity-catalog-azure/entrypoint.sh /usr/local/bin/unitycatalog-azure-entrypoint.sh
RUN chmod +x /usr/local/bin/unitycatalog-azure-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/unitycatalog-azure-entrypoint.sh"]
