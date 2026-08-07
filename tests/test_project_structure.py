"""Project structure validation tests.

Verifies the expected directory layout for the open-lakehouse demo platform.
"""

import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


class TestTopLevel:
    def test_lakehouse_cli_exists(self):
        cli = PROJECT_ROOT / "lakehouse"
        assert cli.exists() and os.access(
            cli, os.X_OK
        ), "lakehouse CLI missing or not executable"

    def test_required_root_files(self):
        for name in (
            "README.md",
            "LICENSE",
            "NOTICE",
            "SECURITY.md",
            "CLAUDE.md",
            "AGENTS.md",
            "pyproject.toml",
        ):
            assert (PROJECT_ROOT / name).exists(), f"missing root file: {name}"


class TestComposeFiles:
    EXPECTED = (
        "docker-compose-spark41.yml",
        "docker-compose-kafka.yml",
        "docker-compose-airflow.yml",
        "docker-compose-unity-catalog.yml",
        "docker-compose-mlflow.yml",
        "docker-compose-notebooks.yml",
    )

    def test_compose_files_present(self):
        for name in self.EXPECTED:
            assert (PROJECT_ROOT / name).exists(), f"missing compose file: {name}"

    def test_spark_40_compose_absent(self):
        assert not (
            PROJECT_ROOT / "docker-compose.yml"
        ).exists(), (
            "docker-compose.yml (Spark 4.0) should not exist in Spark-4.1-only repo"
        )


class TestDirectories:
    EXPECTED_DIRS = (
        "demos",
        "demos/_template",
        "demos/sdp-medallion",
        "demos/unity-catalog-multi-engine",
        "demos/realtime-mode",
        "demos/local-mode-spark",
        "docs",
        "scripts",
        "scripts/tools",
        "scripts/connectivity",
        "scripts/testdata",
        "tests",
        "tests/integration",
        "config/spark",
        "config/unity-catalog",
        "config/mlflow",
        "schemas",
        "terraform",
        "terraform-azure",
        "terraform-databricks",
        "scripts/azure",
        "docker/azure",
        "docker/azure/mlflow-azure",
        "docker/azure/unity-catalog-azure",
        "docker/azure/spark-connect-azure",
        "docker/azure/airflow-azure",
        ".claude/skills/lakehouse-lifecycle",
    )

    def test_expected_dirs_exist(self):
        for d in self.EXPECTED_DIRS:
            assert (PROJECT_ROOT / d).is_dir(), f"missing directory: {d}"

    def test_dropped_demos_are_absent(self):
        dropped = (
            "streaming-kafka-to-iceberg",
            "delta-vs-iceberg",
            "mlflow-tracking",
            "airflow-orchestration",
        )
        for d in dropped:
            assert not (
                PROJECT_ROOT / "demos" / d
            ).exists(), f"old demo dir should not exist: demos/{d}"


class TestConnectFirst:
    """Connect-first architecture invariants."""

    def test_compose_defines_connect_service(self):
        compose = (PROJECT_ROOT / "docker-compose-spark41.yml").read_text()
        assert "spark-connect-41" in compose, "spark-connect-41 service missing"
        assert "15002" in compose, "Connect gRPC port 15002 missing"

    def test_cli_documents_flag(self):
        cli = (PROJECT_ROOT / "lakehouse").read_text()
        assert "--spark-connect" in cli, "--spark-connect flag missing in CLI"
        assert "--spark-local" in cli, "--spark-local stub missing in CLI"
        assert "LAKEHOUSE_SPARK_REMOTE" in cli, "Spark remote env var not exported"

    def test_local_mode_demo_placeholder_exists(self):
        readme = PROJECT_ROOT / "demos" / "local-mode-spark" / "README.md"
        assert (
            readme.exists()
        ), "demos/local-mode-spark/README.md must back the CLI message"
        content = readme.read_text()
        assert "NOT YET IMPLEMENTED" in content, "Placeholder must flag deferred state"


class TestAzureDocker:
    EXPECTED_IMAGES = (
        "mlflow-azure",
        "unity-catalog-azure",
        "spark-connect-azure",
        "airflow-azure",
    )

    def test_azure_runtime_dockerfiles_exist(self):
        for image in self.EXPECTED_IMAGES:
            assert (
                PROJECT_ROOT / "docker" / "azure" / image / "Dockerfile"
            ).exists(), f"missing Dockerfile for {image}"
            assert (
                PROJECT_ROOT / "docker" / "azure" / image / "entrypoint.sh"
            ).exists(), f"missing entrypoint for {image}"


class TestAzureAirflow:
    def test_validation_dag_exists(self):
        dag = PROJECT_ROOT / "dags" / "azure_lakehouse_validation.py"
        assert dag.exists(), "missing Azure validation DAG"
        content = dag.read_text()
        assert "azure_lakehouse_validation" in content, "DAG id missing"
        assert "check_postgres" in content, "Postgres check task missing"
        assert "check_spark_connect" in content, "Spark Connect check task missing"
        assert "check_unity_catalog" in content, "Unity Catalog check task missing"
        assert "check_mlflow" in content, "MLflow check task missing"
        assert "check_kafka_bootstrap" in content, "Kafka bootstrap check task missing"

    def test_terraform_has_airflow_fernet_key_secret(self):
        main_tf = (PROJECT_ROOT / "terraform-azure" / "main.tf").read_text()
        assert "azurerm_key_vault_secret.airflow_fernet_key" in main_tf
        assert "airflow-fernet-key" in main_tf
        assert "AIRFLOW__CORE__FERNET_KEY" in main_tf


class TestAIScaffolding:
    def test_claude_md_under_cap(self):
        content = (PROJECT_ROOT / "CLAUDE.md").read_text()
        assert content.count("\n") < 200, "CLAUDE.md exceeds ~200-line soft cap"

    def test_agents_md_is_pointer(self):
        content = (PROJECT_ROOT / "AGENTS.md").read_text()
        assert content.count("\n") < 30, "AGENTS.md should be a short pointer file"
        assert "CLAUDE.md" in content, "AGENTS.md should forward to CLAUDE.md"

    def test_lifecycle_skill_present(self):
        skill = PROJECT_ROOT / ".claude/skills/lakehouse-lifecycle/SKILL.md"
        assert skill.exists(), "lakehouse-lifecycle skill missing"
