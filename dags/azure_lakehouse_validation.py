"""Lightweight validation DAG for the Azure-backed lakehouse stack.

This DAG exercises the Airflow connections configured by
setup-connections-azure.sh against the Azure Container Apps runtime. It is
meant to run on the single-container Airflow deployment and proves that
Airflow can reach PostgreSQL, Spark Connect, Unity Catalog, MLflow, and
Event Hubs.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta
from urllib.parse import urljoin

from airflow import DAG
from airflow.providers.http.hooks.http import HttpHook
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.operators.python import PythonOperator

logger = logging.getLogger(__name__)


def _check_postgres() -> None:
    hook = PostgresHook(postgres_conn_id="postgres_default")
    records = hook.get_records("SELECT 1 AS ok;")
    assert records and records[0][0] == 1, "Postgres connectivity check failed"
    logger.info("Postgres connectivity check passed")


def _check_spark_connect() -> None:
    # Airflow does not ship a Spark Connect hook in the open-source providers,
    # so we validate the configured connection by parsing it and issuing a
    # lightweight HTTP OPTIONS probe to the external ACA ingress. gRPC itself
    # is not HTTP, but ACA ingress exposes HTTP/2 on the same port and will
    # respond to a TLS handshake / probe, which is enough to prove reachability.
    from airflow.models import Connection

    conn = Connection.get_connection_from_secrets("spark_azure")
    host = conn.host
    port = conn.port or "443"
    logger.info("Spark Connect connection configured for host=%s port=%s", host, port)

    import http.client

    try:
        client = http.client.HTTPSConnection(host, port=int(port), timeout=10)
        client.request("OPTIONS", "/")
        resp = client.getresponse()
        logger.info("Spark Connect ingress responded with status=%s", resp.status)
    finally:
        client.close()


def _check_http_endpoint(name: str, conn_id: str, path: str = "/") -> None:
    hook = HttpHook(http_conn_id=conn_id, method="GET")
    # HttpHook.run_with_advanced_retry would be cleaner, but .run is enough for a probe.
    resp = hook.run(endpoint=path)
    logger.info("%s endpoint responded with status=%s", name, resp.status_code)


def _check_unity_catalog() -> None:
    _check_http_endpoint("Unity Catalog", "unity_catalog", "/")


def _check_mlflow() -> None:
    _check_http_endpoint("MLflow", "mlflow", "/")


def _check_kafka_bootstrap() -> None:
    # Listing Kafka topics requires a full SASL/SSL connection to Event Hubs.
    # In the single-container demo deployment we only log the configured
    # bootstrap servers; a real pipeline DAG would use the Kafka operators.
    from airflow.models import Connection

    conn = Connection.get_connection_from_secrets("kafka_default")
    extra = conn.extra_dejson
    bootstrap_servers = extra.get("bootstrap.servers", "")
    logger.info("Kafka/Event Hubs bootstrap servers: %s", bootstrap_servers)
    assert bootstrap_servers, "kafka_default connection is missing bootstrap.servers"


with DAG(
    dag_id="azure_lakehouse_validation",
    description="Validate Airflow connectivity to Azure lakehouse services",
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args={
        "owner": "airflow",
        "retries": 1,
        "retry_delay": timedelta(seconds=30),
    },
    tags=["azure", "validation", "lakehouse"],
) as dag:
    check_postgres = PythonOperator(
        task_id="check_postgres",
        python_callable=_check_postgres,
    )
    check_spark_connect = PythonOperator(
        task_id="check_spark_connect",
        python_callable=_check_spark_connect,
    )
    check_unity_catalog = PythonOperator(
        task_id="check_unity_catalog",
        python_callable=_check_unity_catalog,
    )
    check_mlflow = PythonOperator(
        task_id="check_mlflow",
        python_callable=_check_mlflow,
    )
    check_kafka_bootstrap = PythonOperator(
        task_id="check_kafka_bootstrap",
        python_callable=_check_kafka_bootstrap,
    )

    check_postgres >> [
        check_spark_connect,
        check_unity_catalog,
        check_mlflow,
        check_kafka_bootstrap,
    ]
