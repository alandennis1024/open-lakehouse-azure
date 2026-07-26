# Azure deployment scaffold

This folder contains a first-pass Terraform implementation for Azure resources that can host the lakehouse platform.

## What it provisions

- Azure Resource Group
- Azure Storage Account with ADLS Gen2 enabled
- Azure Storage Container for warehouse data
- Azure Key Vault
- Azure Database for PostgreSQL Flexible Server
- Azure Event Hubs namespace and event hub
- Azure Log Analytics workspace

## Quick start

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your own values.

3. Initialize Terraform:

   ```bash
   terraform init
   ```

4. Preview the deployment:

   ```bash
   terraform plan -var-file=terraform.tfvars
   ```

5. Apply it:

   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

## Notes

- The storage account name must be globally unique.
- The PostgreSQL password must satisfy Azure’s password policy.
- The current scaffold is intentionally minimal and should be extended with networking, private endpoints, and container-based compute resources in the next iteration.
