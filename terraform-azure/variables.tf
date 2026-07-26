variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "lakehouse-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Prefix for resources"
  type        = string
  default     = "lakehouse"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "storage_account_name" {
  description = "Globally unique Azure Storage account name"
  type        = string
}

variable "storage_container_name" {
  description = "Azure Storage container for warehouse data"
  type        = string
  default     = "warehouse"
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
}

variable "acr_name" {
  description = "Name of the Azure Container Registry"
  type        = string
}

variable "azure_sp_client_id" {
  description = "Azure Service Principal client ID for ADLS access"
  type        = string
  sensitive   = true
}

variable "azure_sp_client_secret" {
  description = "Azure Service Principal client secret for ADLS access"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure Tenant ID for ADLS access"
  type        = string
  sensitive   = true
}

variable "allowed_client_ip" {
  description = "Client IP address to allow through PostgreSQL firewall"
  type        = string
  default     = ""
}

variable "postgres_server_name" {
  description = "Azure PostgreSQL flexible server name"
  type        = string
}

variable "postgres_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "lakehouse"
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}

variable "postgres_sku_name" {
  description = "SKU for Azure PostgreSQL flexible server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_database_name" {
  description = "Database name for catalog metadata"
  type        = string
  default     = "iceberg_catalog"
}

variable "eventhub_namespace_name" {
  description = "Event Hubs namespace name"
  type        = string
}

variable "eventhub_name" {
  description = "Event Hub name"
  type        = string
  default     = "lakehouse-events"
}

variable "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  type        = string
}

variable "mlflow_image" {
  description = "Container image for MLflow. Defaults to the ACR-hosted image."
  type        = string
  default     = null
}

variable "unity_catalog_image" {
  description = "Container image for Unity Catalog OSS. Defaults to the ACR-hosted image."
  type        = string
  default     = null
}
