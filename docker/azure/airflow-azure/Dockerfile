# Airflow 3.1.6 runtime for Azure Container Apps.
#
# Runs API server, scheduler, and triggerer in a single container via supervisord
# to keep the demo scaffold low-cost. DAGs are baked into the image at build time.

FROM apache/airflow:3.1.6-python3.12

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    curl \
    supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Airflow providers used by the lakehouse demos.
RUN pip install --no-cache-dir \
    apache-airflow-providers-apache-spark==5.5.0 \
    apache-airflow-providers-postgres==5.14.0 \
    apache-airflow-providers-apache-kafka==1.8.0 \
    apache-airflow-providers-http==5.6.3 \
    pyspark==4.1.0

# Bake the repo DAGs into the image. For production, use a volume or git-sync.
COPY dags /opt/airflow/dags
RUN chown -R airflow:root /opt/airflow/dags

COPY docker/azure/airflow-azure/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/azure/airflow-azure/entrypoint.sh /usr/local/bin/airflow-azure-entrypoint.sh
COPY docker/azure/airflow-azure/setup-connections-azure.sh /usr/local/bin/setup-connections-azure.sh
RUN chmod +x /usr/local/bin/airflow-azure-entrypoint.sh /usr/local/bin/setup-connections-azure.sh

WORKDIR /opt/airflow

ENTRYPOINT ["/usr/local/bin/airflow-azure-entrypoint.sh"]
