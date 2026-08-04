"""Tests for scripts/azure/generate-config.sh."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest


@pytest.fixture
def fake_repo(tmp_path):
    """Create a minimal repo tree that generate-config.sh can run against."""
    repo_root = Path(__file__).resolve().parents[1]
    repo = tmp_path / "repo"

    (repo / "terraform-azure").mkdir(parents=True)
    (repo / "config" / "spark").mkdir(parents=True)
    (repo / "config" / "unity-catalog").mkdir(parents=True)

    # Copy example files so the generator has a base to transform.
    shutil.copyfile(
        repo_root / "config" / "spark" / "spark-defaults.conf.example",
        repo / "config" / "spark" / "spark-defaults.conf.example",
    )
    shutil.copyfile(
        repo_root / "config" / "unity-catalog" / "server.properties.example",
        repo / "config" / "unity-catalog" / "server.properties.example",
    )

    return repo


def _fake_terraform_script(tmp_path, values):
    """Write a fake `terraform` binary that echoes canned output values."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    terraform = bin_dir / "terraform"

    lookup = []
    for name, value in values.items():
        lookup.append(f'  "{name}") echo "{value}" ;;')

    script = (
        "#!/usr/bin/env bash\n"
        'case "$4" in\n' + "\n".join(lookup) + "\n"
        "  *) exit 1 ;;\n"
        "esac\n"
    )

    terraform.write_text(script)
    terraform.chmod(0o755)
    return bin_dir


def test_generate_config_creates_azure_profile_files(fake_repo, tmp_path):
    repo_root = Path(__file__).resolve().parents[1]

    outputs = {
        "resource_group_name": "lakehouse-rg",
        "storage_account_name": "lakehouse0001",
        "storage_account_primary_blob_endpoint": "https://lakehouse0001.blob.core.windows.net",
        "storage_account_primary_access_key": "fake-access-key",
        "storage_container_name": "warehouse",
        "mlflow_artifacts_container_name": "mlflow-artifacts",
        "postgres_fqdn": "lakehouse-postgres.postgres.database.azure.com",
        "postgres_admin_username": "lakehouse",
        "eventhub_namespace_name": "lakehouse-ehns",
        "eventhub_namespace_connection_string": "Endpoint=sb://lakehouse-ehns.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=fake-key",
        "eventhub_name": "lakehouse-events",
        "key_vault_name": "lakehouse-kv",
        "key_vault_uri": "https://lakehouse-kv.vault.azure.net/",
        "acr_login_server": "lakehouseacr.azurecr.io",
        "unity_catalog_url": "https://unity-catalog.kind-sea-1234.azurecontainerapps.io",
        "mlflow_url": "https://mlflow.kind-sea-1234.azurecontainerapps.io",
        "spark_connect_url": "sc://spark-connect.kind-sea-1234.azurecontainerapps.io:443/;use_ssl=true",
        "spark_connect_fqdn": "spark-connect.kind-sea-1234.azurecontainerapps.io",
        "airflow_url": "https://airflow.kind-sea-1234.azurecontainerapps.io",
    }
    fake_bin = _fake_terraform_script(tmp_path, outputs)

    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
    env["AZURE_GENERATE_CONFIG_ROOT"] = str(fake_repo)
    env["AZURE_POSTGRES_ADMIN_PASSWORD"] = "StrongPassword123!"
    env["AZURE_SP_CLIENT_ID"] = "00000000-0000-0000-0000-000000000001"
    env["AZURE_SP_CLIENT_SECRET"] = "super-secret"
    env["AZURE_TENANT_ID"] = "00000000-0000-0000-0000-000000000002"
    env["AZURE_AIRFLOW_ADMIN_USER"] = "airflow"
    env["AZURE_AIRFLOW_ADMIN_PASSWORD"] = "AirflowPass123!"

    result = subprocess.run(
        ["bash", str(repo_root / "scripts" / "azure" / "generate-config.sh")],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    env_azure = fake_repo / ".env.azure"
    spark_azure = fake_repo / "config" / "spark" / "spark-defaults.conf.azure"
    uc_azure = fake_repo / "config" / "unity-catalog" / "server.properties.azure"

    assert env_azure.exists()
    assert spark_azure.exists()
    assert uc_azure.exists()

    env_text = env_azure.read_text()
    assert "LAKEHOUSE_PROFILE=azure" in env_text
    assert "lakehouse-postgres.postgres.database.azure.com" in env_text
    assert "lakehouse0001" in env_text
    assert "lakehouse-ehns.servicebus.windows.net:9093" in env_text
    assert "AZURE_SP_CLIENT_ID=00000000-0000-0000-0000-000000000001" in env_text
    assert "LAKEHOUSE_SPARK_MODE=connect" in env_text
    assert (
        "LAKEHOUSE_SPARK_REMOTE=sc://spark-connect.kind-sea-1234.azurecontainerapps.io:443/;use_ssl=true"
        in env_text
    )
    assert "AIRFLOW_UI_URL=https://airflow.kind-sea-1234.azurecontainerapps.io" in env_text
    assert "AIRFLOW_ADMIN_USER=airflow" in env_text
    assert "AIRFLOW_ADMIN_PASSWORD=AirflowPass123!" in env_text

    spark_text = spark_azure.read_text()
    assert "abfs://warehouse@lakehouse0001.dfs.core.windows.net/" in spark_text
    assert "ClientCredsTokenProvider" in spark_text
    assert "spark.sql.catalog.unity.uri" in spark_text
    assert "hadoop-azure-3.4.1.jar" in spark_text

    uc_text = uc_azure.read_text()
    assert "adls.storageAccountName.0=lakehouse0001" in uc_text
    assert "adls.tenantId.0=00000000-0000-0000-0000-000000000002" in uc_text
    assert "lakehouse-postgres.postgres.database.azure.com" in uc_text

    # No placeholder values should remain in generated files.
    placeholders = (
        "your_username",
        "your_password",
        "your_access_key",
        "your_secret_key",
        "ChangeMe",
        "<storage-account>",
        "<storage-account-name>",
        "<client-id>",
        "<client-secret>",
        "<tenant-id>",
    )
    for text in (env_text, spark_text, uc_text):
        for placeholder in placeholders:
            assert (
                placeholder not in text
            ), f"found placeholder {placeholder!r} in generated file"
