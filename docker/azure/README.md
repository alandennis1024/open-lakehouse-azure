# Azure runtime images

This directory contains Docker images used by the Azure Container Apps runtime
layer in `terraform-azure/`.

| Image | Purpose |
|-------|---------|
| `mlflow-azure` | MLflow tracking server backed by Azure PostgreSQL and Azure Blob Storage |
| `unity-catalog-azure` | Unity Catalog OSS server configured at runtime for Azure PostgreSQL and ADLS Gen2 |
| `spark-connect-azure` | Spark 4.1 Connect server (gRPC) backed by Unity Catalog OSS and ADLS Gen2 |

## Build and push

After running `just azure-generate-config` (which sets `AZURE_ACR_LOGIN_SERVER`):

```bash
just azure-runtime-build mlflow-azure 3.13.0
just azure-runtime-build unity-catalog-azure v0.4.1
just azure-runtime-build spark-connect-azure v0.1.0
```

These images are referenced by the `mlflow_image`, `unity_catalog_image`, and
`spark_connect_image` variables in `terraform-azure/`. The defaults assume
the ACR repository prefix `lakehouse/` and the tags shown above.
