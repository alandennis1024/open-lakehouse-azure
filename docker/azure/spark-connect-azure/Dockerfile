# Spark 4.1 Connect server for Azure Container Apps.
#
# Self-contained image for the Azure deployment profile. Bundles the same
# Iceberg/Delta/UC/ABFS JARs used locally so Spark Connect can read and write
# ADLS Gen2 via Unity Catalog OSS without runtime package downloads.

FROM apache/spark:4.1.0-scala2.13-java21-python3-r-ubuntu

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Extra JARs are supplied by ./lakehouse setup (scripts/tools/download-jars.sh).
# Copy everything so the runtime classpath picks up Iceberg, Delta, UC, ABFS, etc.
COPY jars /opt/spark/jars-extra

COPY docker/azure/spark-connect-azure/entrypoint.sh /usr/local/bin/spark-connect-azure-entrypoint.sh
RUN chmod +x /usr/local/bin/spark-connect-azure-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/spark-connect-azure-entrypoint.sh"]
