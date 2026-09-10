output "resource_group_name" {
  value = azurerm_resource_group.lakehouse.name
}

output "storage_account_name" {
  value = azurerm_storage_account.lakehouse.name
}

output "storage_account_primary_blob_endpoint" {
  value = azurerm_storage_account.lakehouse.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  value     = azurerm_storage_account.lakehouse.primary_access_key
  sensitive = true
}

output "storage_container_name" {
  value = azurerm_storage_container.warehouse.name
}

output "mlflow_artifacts_container_name" {
  value = azurerm_storage_container.mlflow_artifacts.name
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.lakehouse.fqdn
}

output "postgres_admin_username" {
  value = var.postgres_admin_username
}

output "eventhub_namespace_name" {
  value = azurerm_eventhub_namespace.lakehouse.name
}

output "eventhub_namespace_connection_string" {
  value     = azurerm_eventhub_namespace_authorization_rule.lakehouse.primary_connection_string
  sensitive = true
}

output "eventhub_name" {
  value = azurerm_eventhub.lakehouse.name
}

output "key_vault_name" {
  value = azurerm_key_vault.lakehouse.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.lakehouse.vault_uri
}

output "acr_login_server" {
  value = azurerm_container_registry.lakehouse.login_server
}

output "unity_catalog_url" {
  value = "https://${azurerm_container_app.unity_catalog.ingress[0].fqdn}"
}

output "mlflow_url" {
  value = "https://${azurerm_container_app.mlflow.ingress[0].fqdn}"
}

output "spark_connect_fqdn" {
  value = azurerm_container_app.spark_connect.ingress[0].fqdn
}

output "spark_connect_url" {
  value         = "sc://${azurerm_container_app.spark_connect.ingress[0].fqdn}:443/;use_ssl=true"
  description   = "Spark Connect gRPC endpoint. Port 443 is the ACA external HTTPS/HTTP2 ingress port; use_ssl=true enables TLS on the client."
}

output "airflow_url" {
  value = "https://${azurerm_container_app.airflow.ingress[0].fqdn}"
}
