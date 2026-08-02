# Azure deployment for open-lakehouse

This guide covers the first-milestone Azure deployment for the lakehouse stack.
The repository remains Docker-first locally; Azure is an opt-in overlay that is
activated with a deployment profile.

## What the first milestone deploys

The `terraform-azure/` module provisions the following Azure resources:

| Resource | Purpose |
|----------|---------|
| Resource group | Container for all Azure resources |
| Azure Container Registry | Hosts the MLflow, Unity Catalog, and Spark Connect runtime images |
| Storage account (ADLS Gen2) | Lakehouse warehouse data and MLflow artifacts |
| Azure Database for PostgreSQL Flexible Server | Metadata store for Unity Catalog OSS and MLflow |
| Azure Event Hubs namespace | Kafka-compatible streaming endpoint |
| Azure Key Vault | Secret management |
| Azure Container Apps environment | Runtime host for Unity Catalog OSS, MLflow, and Spark Connect |

The milestone deploys **Unity Catalog OSS**, **MLflow**, and **Spark Connect** as
Container Apps. Airflow runtime hosting is the next slice.

## Deployment profile

The `lakehouse` CLI supports an explicit deployment profile via the
`LAKEHOUSE_PROFILE` environment variable or the `--profile` flag:

```bash
# Use the local Docker-first stack (default)
./lakehouse setup
LAKEHOUSE_PROFILE=local ./lakehouse setup

# Target Azure-backed services
LAKEHOUSE_PROFILE=azure ./lakehouse setup
./lakehouse --profile azure setup
./lakehouse --profile azure preflight
```

When the profile is `azure`, the CLI:

1. Sources `.env` as usual.
2. Sources `.env.azure` if it exists, so Azure endpoints override local values.
3. Prints a short notice that the Azure profile is active.
4. Warns if any Azure profile files are missing during `setup` and `preflight`.

The generated Azure profile files are:

| File | Purpose |
|------|---------|
| `.env.azure` | Azure endpoints, credentials, and service-principal settings |
| `config/spark/spark-defaults.conf.azure` | Spark ABFS / Unity Catalog configuration |
| `config/unity-catalog/server.properties.azure` | Unity Catalog ADLS and PostgreSQL settings |

## Workflow

### 0. Install prerequisites

If you haven't installed the platform tools yet, run the prereq installer
first:

```bash
bash scripts/tools/install-prereqs.sh --auto
```

This installs Docker, Poetry, `just`, Terraform, Azure CLI, Java, psql, and
ShellCheck where possible.

### 1. Bootstrap Terraform variables

Export the required Azure variables and run the bootstrap recipe:

```bash
export AZURE_RESOURCE_GROUP_NAME=lakehouse-rg
export AZURE_LOCATION=eastus
export AZURE_STORAGE_ACCOUNT_NAME=lakehouse0001
export AZURE_KEY_VAULT_NAME=lakehouse-kv
export AZURE_POSTGRES_SERVER_NAME=lakehouse-postgres
export AZURE_POSTGRES_ADMIN_PASSWORD='StrongPassword123!'
export AZURE_EVENTHUB_NAMESPACE_NAME=lakehouse-ehns
export AZURE_LOG_ANALYTICS_WORKSPACE_NAME=lakehouse-law

just azure-bootstrap
```

### 2. Build and push runtime images

The Container Apps expect MLflow, Unity Catalog, and Spark Connect images in
the deployed ACR. Build and push them before applying the runtime layer:

```bash
just azure-runtime-build mlflow-azure 3.13.0
just azure-runtime-build unity-catalog-azure v0.4.1
just azure-runtime-build spark-connect-azure v0.1.0
```

### 3. Plan and apply the Azure scaffold

```bash
just azure-plan
just azure-apply
```

### 4. Generate the Azure profile configuration

The `generate-config.sh` script reads `terraform-azure` outputs and creates the
three `.azure` files. Provide the service-principal credentials and PostgreSQL
password as environment variables (they are not exported by Terraform):

```bash
export AZURE_SP_CLIENT_ID='...'
export AZURE_SP_CLIENT_SECRET='...'
export AZURE_TENANT_ID='...'
export AZURE_POSTGRES_ADMIN_PASSWORD='...'

just azure-generate-config
```

The Spark Connect endpoint is exposed through the Azure Container Apps HTTPS
ingress on port 443. The generated `.env.azure` sets:

```bash
LAKEHOUSE_SPARK_MODE=connect
LAKEHOUSE_SPARK_REMOTE=sc://<spark-connect-fqdn>:443/;use_ssl=true
```

Connect from any Python:

```python
import os
from pyspark.sql import SparkSession
spark = SparkSession.builder.remote(os.environ["LAKEHOUSE_SPARK_REMOTE"]).getOrCreate()
spark.sql("SHOW CATALOGS").show()
```

Review the generated files. To copy them to the active locations used by the
runtime, run with `--apply`:

```bash
just azure-generate-config --apply
```

This copies:

- `.env.azure` → `.env` (backs up the existing `.env`)
- `config/spark/spark-defaults.conf.azure` → `config/spark/spark-defaults.conf`
- `config/unity-catalog/server.properties.azure` → `config/unity-catalog/server.properties`

### 5. Validate the Azure profile

```bash
./lakehouse --profile azure setup
./lakehouse --profile azure preflight
```

## just recipes

| Recipe | Purpose |
|--------|---------|
| `just azure-bootstrap` | Create `terraform-azure/terraform.tfvars` from environment variables |
| `just azure-plan` | Plan the Azure scaffold |
| `just azure-apply` | Apply the Azure scaffold |
| `just azure-generate-config` | Generate Azure profile files from Terraform outputs |
| `just azure-generate-config --apply` | Generate and apply Azure profile files |
| `just azure-destroy` | Tear down the Azure scaffold |
| `just azure-runtime-build <image> [tag]` | Build and push a runtime image to ACR |

## Configuration reference

The generated `.env.azure` sets these variables:

```bash
LAKEHOUSE_PROFILE=azure

POSTGRES_HOST=<postgres-fqdn>
POSTGRES_USER=<admin-username>
POSTGRES_PASSWORD=<admin-password>

AZURE_STORAGE_ACCOUNT_NAME=<storage-account>
AZURE_STORAGE_CONTAINER_NAME=<container>
AZURE_STORAGE_BLOB_ENDPOINT=<blob-endpoint>
AZURE_STORAGE_PRIMARY_ACCESS_KEY=<account-key>

AZURE_EVENTHUB_NAMESPACE=<namespace>
AZURE_EVENTHUB_NAME=<eventhub>
KAFKA_BOOTSTRAP_SERVERS=<namespace>.servicebus.windows.net:9093

AZURE_KEY_VAULT_NAME=<key-vault>
AZURE_KEY_VAULT_URI=<key-vault-uri>
AZURE_ACR_LOGIN_SERVER=<acr>.azurecr.io

UNITY_CATALOG_URI=<unity-catalog-url>
MLFLOW_TRACKING_URI=<mlflow-url>
LAKEHOUSE_SPARK_MODE=connect
LAKEHOUSE_SPARK_REMOTE=sc://<spark-connect-fqdn>:443/;use_ssl=true

AZURE_SP_CLIENT_ID=<client-id>
AZURE_SP_CLIENT_SECRET=<client-secret>
AZURE_TENANT_ID=<tenant-id>
```

The Spark `.azure` config uses ABFS with OAuth by default and points the Unity
Catalog URI at the Azure-hosted endpoint. The Unity Catalog `server.properties.azure`
configures ADLS Gen2 access via the four service-principal keys and connects to
the Azure PostgreSQL backend.

## Security defaults

- **ACR pull uses a user-assigned managed identity.** The ACR admin account is
  disabled. Container Apps authenticate to ACR with the same identity they use
  to read Key Vault secrets.
- **Runtime secrets are Key Vault references.** Postgres passwords, storage
  account keys, and the service-principal secret are never passed as plaintext
  environment variables in the Container App definitions; they are pulled at
  runtime from Key Vault.
- **PostgreSQL public network access is enabled by default** (Azure services +
  optional client IP only) so the Container Apps can reach it without a private
  VNet. Set `postgres_public_network_access_enabled = false` only after adding
  a private endpoint or VNet integration.

## Cost defaults

This scaffold is intentionally cheap for demos and PoCs:

- Container Apps: **Consumption**, single replica per app.
- PostgreSQL: **B_Standard_B1ms** burstable SKU.
- Storage: **Standard LRS** with HNS (ADLS Gen2).
- Event Hubs: **Standard**, 1 throughput unit.
- ACR: **Standard** SKU.
- Spark Connect runs on a single **1 vCPU / 2 GiB** container in `local[*]`
  mode (no separate master/worker cost).

## Notes and caveats

- The local Docker stack is unchanged. Keep `LAKEHOUSE_PROFILE` unset or set to
  `local` for local development.
- Azure storage authentication uses service-principal OAuth by default. Account
  key auth is commented in the generated Spark config as a fallback.
- Event Hubs uses the Kafka-compatible endpoint, so existing Kafka-style
  producer/consumer scripts work with `KAFKA_BOOTSTRAP_SERVERS`.
- Spark Connect is exposed through Azure Container Apps HTTP/2 ingress. The
  gRPC transport is plaintext inside the environment; TLS is terminated at the
  ACA ingress. Use `sc://<fqdn>:443` from clients.
- The next slice is Airflow runtime hosting on Azure Container Apps.
