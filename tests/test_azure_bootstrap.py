import os
import subprocess
from pathlib import Path


def test_bootstrap_creates_terraform_tfvars(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    bootstrap_root = tmp_path / "repo"
    (bootstrap_root / "terraform-azure").mkdir(parents=True)

    env = os.environ.copy()
    env["AZURE_BOOTSTRAP_ROOT"] = str(bootstrap_root)
    env["AZURE_RESOURCE_GROUP_NAME"] = "lakehouse-rg"
    env["AZURE_LOCATION"] = "eastus"
    env["AZURE_STORAGE_ACCOUNT_NAME"] = "lakehouse0001"
    env["AZURE_KEY_VAULT_NAME"] = "lakehouse-kv"
    env["AZURE_POSTGRES_SERVER_NAME"] = "lakehouse-postgres"
    env["AZURE_POSTGRES_ADMIN_PASSWORD"] = "StrongPassword123!"
    env["AZURE_EVENTHUB_NAMESPACE_NAME"] = "lakehouse-ehns"
    env["AZURE_LOG_ANALYTICS_WORKSPACE_NAME"] = "lakehouse-law"

    result = subprocess.run(
        ["bash", "scripts/azure/bootstrap.sh"],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    tfvars_file = bootstrap_root / "terraform-azure" / "terraform.tfvars"
    assert tfvars_file.exists()

    content = tfvars_file.read_text()
    assert 'resource_group_name        = "lakehouse-rg"' in content
    assert 'storage_account_name       = "lakehouse0001"' in content


def test_bootstrap_creates_env_azure_skeleton(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    bootstrap_root = tmp_path / "repo"
    (bootstrap_root / "terraform-azure").mkdir(parents=True)

    env = os.environ.copy()
    env["AZURE_BOOTSTRAP_ROOT"] = str(bootstrap_root)
    env["AZURE_RESOURCE_GROUP_NAME"] = "lakehouse-rg"
    env["AZURE_LOCATION"] = "eastus"
    env["AZURE_STORAGE_ACCOUNT_NAME"] = "lakehouse0001"
    env["AZURE_KEY_VAULT_NAME"] = "lakehouse-kv"
    env["AZURE_POSTGRES_SERVER_NAME"] = "lakehouse-postgres"
    env["AZURE_POSTGRES_ADMIN_PASSWORD"] = "StrongPassword123!"
    env["AZURE_EVENTHUB_NAMESPACE_NAME"] = "lakehouse-ehns"
    env["AZURE_LOG_ANALYTICS_WORKSPACE_NAME"] = "lakehouse-law"

    # Extra variables required for the .env.azure skeleton
    env["AZURE_POSTGRES_HOST"] = "lakehouse-postgres.postgres.database.azure.com"
    env["AZURE_POSTGRES_PORT"] = "5432"
    env["AZURE_POSTGRES_USER"] = "lakehouse"
    env["AZURE_POSTGRES_DB"] = "iceberg_catalog"
    env["AZURE_EVENTHUB_NAMESPACE"] = "lakehouse-ehns"
    env["AZURE_EVENTHUB_NAME"] = "lakehouse-events"
    env["AZURE_SP_CLIENT_ID"] = "00000000-0000-0000-0000-000000000001"
    env["AZURE_SP_CLIENT_SECRET"] = "secret-value"
    env["AZURE_TENANT_ID"] = "00000000-0000-0000-0000-000000000002"

    result = subprocess.run(
        ["bash", "scripts/azure/bootstrap.sh"],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    env_azure = bootstrap_root / ".env.azure"
    assert env_azure.exists(), result.stdout + result.stderr

    content = env_azure.read_text()
    assert "LAKEHOUSE_PROFILE=azure" in content
    assert "lakehouse-postgres.postgres.database.azure.com" in content
    assert "AZURE_STORAGE_ACCOUNT_NAME=lakehouse0001" in content
    assert "AZURE_SP_CLIENT_ID=00000000-0000-0000-0000-000000000001" in content
