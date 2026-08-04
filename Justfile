# open-lakehouse — just recipes
# https://github.com/casey/just

# Default recipe: show help
help:
    @echo "open-lakehouse just recipes"
    @echo ""
    @echo "Azure deployment recipes:"
    @echo "  just azure-bootstrap                 Create terraform.tfvars from env vars"
    @echo "  just azure-plan                     Plan the Azure scaffold"
    @echo "  just azure-apply                    Apply the Azure scaffold"
    @echo "  just azure-destroy                  Tear down the Azure scaffold"
    @echo "  just azure-generate-config          Generate Azure profile files"
    @echo "  just azure-generate-config --apply  Generate and copy to active locations"
    @echo "  just azure-runtime-build <image> [tag]  Build and push a runtime image to ACR"
    @echo "    images: mlflow-azure, unity-catalog-azure, spark-connect-azure, airflow-azure"
    @echo ""
    @echo "Local recipes:"
    @echo "  just setup                          Run ./lakehouse setup"
    @echo "  just test                           Run pytest unit tests"

# Azure bootstrap — create terraform.tfvars from environment variables
azure-bootstrap:
    bash scripts/azure/bootstrap.sh

# Azure plan — preview the Terraform deployment
azure-plan:
    bash scripts/azure/deploy.sh plan

# Azure apply — deploy the Azure scaffold
azure-apply:
    bash scripts/azure/deploy.sh apply

# Azure destroy — tear down the Azure scaffold
azure-destroy:
    bash scripts/azure/deploy.sh destroy

# Azure generate-config — generate Azure profile files from Terraform outputs
azure-generate-config *args:
    bash scripts/azure/generate-config.sh {{args}}

# Azure runtime build — build and push a runtime image to ACR
# Usage: just azure-runtime-build mlflow-azure 3.13.0
#        just azure-runtime-build unity-catalog-azure v0.4.1
#        just azure-runtime-build spark-connect-azure v0.1.0
#        just azure-runtime-build airflow-azure v0.1.0
azure-runtime-build image tag="latest":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${AZURE_ACR_LOGIN_SERVER:-}" ]; then
        echo "AZURE_ACR_LOGIN_SERVER is not set. Run: just azure-generate-config" >&2
        exit 1
    fi
    docker build -t "${AZURE_ACR_LOGIN_SERVER}/lakehouse/{{image}}:{{tag}}" "docker/azure/{{image}}"
    docker push "${AZURE_ACR_LOGIN_SERVER}/lakehouse/{{image}}:{{tag}}"

# Local setup
setup:
    ./lakehouse setup

# Run unit tests (no Docker / integration tests)
test:
    pytest tests/ --ignore=tests/integration -v

# Run security tests
security-test:
    pytest -m security -v

# Validate Terraform and shell scripts
validate:
    bash -n lakehouse
    bash -n scripts/azure/*.sh
    bash -n docker/azure/*/entrypoint.sh
    terraform -chdir=terraform-azure validate

# Lint and format checks
lint:
    ruff check scripts/ tests/ demos/
    black --check scripts/ tests/ demos/
    shellcheck -S warning lakehouse scripts/azure/*.sh docker/azure/*/entrypoint.sh || true
