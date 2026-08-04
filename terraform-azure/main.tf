terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  container_app_environment_name = "${var.project_name}-${var.environment}-cae"
  mlflow_image                   = coalesce(var.mlflow_image, "${azurerm_container_registry.lakehouse.login_server}/lakehouse/mlflow-azure:3.13.0")
  unity_catalog_image            = coalesce(var.unity_catalog_image, "${azurerm_container_registry.lakehouse.login_server}/lakehouse/unity-catalog-azure:v0.4.1")
  spark_connect_image            = coalesce(var.spark_connect_image, "${azurerm_container_registry.lakehouse.login_server}/lakehouse/spark-connect-azure:v0.1.0")
  airflow_image                  = coalesce(var.airflow_image, "${azurerm_container_registry.lakehouse.login_server}/lakehouse/airflow-azure:v0.1.0")
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "lakehouse" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_storage_account" "lakehouse" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.lakehouse.name
  location                 = azurerm_resource_group.lakehouse.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_storage_container" "warehouse" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.lakehouse.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "mlflow_artifacts" {
  name                  = "mlflow-artifacts"
  storage_account_id    = azurerm_storage_account.lakehouse.id
  container_access_type = "private"
}

resource "azurerm_container_registry" "lakehouse" {
  # Admin account is disabled. Container Apps pull with the shared
  # user-assigned managed identity (see azurerm_user_assigned_identity.lakehouse).
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.lakehouse.name
  location            = azurerm_resource_group.lakehouse.location
  sku                 = "Standard"
  admin_enabled       = false

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_user_assigned_identity" "lakehouse" {
  name                = "${var.project_name}-${var.environment}-identity"
  location            = azurerm_resource_group.lakehouse.location
  resource_group_name = azurerm_resource_group.lakehouse.name

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_role_assignment" "lakehouse_acr_pull" {
  scope                = azurerm_container_registry.lakehouse.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.lakehouse.principal_id
}

resource "azurerm_key_vault" "lakehouse" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.lakehouse.location
  resource_group_name = azurerm_resource_group.lakehouse.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

resource "azurerm_key_vault_access_policy" "lakehouse_identity" {
  key_vault_id = azurerm_key_vault.lakehouse.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.lakehouse.principal_id

  secret_permissions = ["Get"]
}

resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.lakehouse.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
}

resource "azurerm_key_vault_secret" "postgres_admin_password" {
  name         = "postgres-admin-password"
  value        = var.postgres_admin_password
  key_vault_id = azurerm_key_vault.lakehouse.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.lakehouse.primary_access_key
  key_vault_id = azurerm_key_vault.lakehouse.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "airflow_admin_password" {
  name         = "airflow-admin-password"
  value        = var.airflow_admin_password
  key_vault_id = azurerm_key_vault.lakehouse.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_eventhub_namespace_authorization_rule" "lakehouse" {
  name                = "RootManageSharedAccessKey"
  namespace_name      = azurerm_eventhub_namespace.lakehouse.name
  resource_group_name = azurerm_resource_group.lakehouse.name

  listen = true
  send   = true
  manage = true
}

resource "azurerm_key_vault_secret" "eventhub_connection_string" {
  name         = "eventhub-connection-string"
  value        = azurerm_eventhub_namespace_authorization_rule.lakehouse.primary_connection_string
  key_vault_id = azurerm_key_vault.lakehouse.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "azure_sp_client_secret" {
  name         = "azure-sp-client-secret"
  value        = var.azure_sp_client_secret
  key_vault_id = azurerm_key_vault.lakehouse.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_postgresql_flexible_server" "lakehouse" {
  name                          = var.postgres_server_name
  resource_group_name           = azurerm_resource_group.lakehouse.name
  location                      = azurerm_resource_group.lakehouse.location
  version                       = "16"
  public_network_access_enabled = var.postgres_public_network_access_enabled
  administrator_login           = var.postgres_admin_username
  administrator_password        = var.postgres_admin_password
  zone                          = "1"
  storage_mb                    = 32768
  sku_name                      = var.postgres_sku_name

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  # Allow only Azure services (not the whole Internet). In Azure, the range
  # 0.0.0.0 - 0.0.0.0 is the documented sentinel for "Azure services" access.
  # This rule is only created when public network access is enabled.
  count            = var.postgres_public_network_access_enabled ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.lakehouse.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "current_client" {
  # Optional dev-only rule for the operator's current public IP. Leave empty
  # for deployments that reach PostgreSQL only from within Azure.
  count            = var.postgres_public_network_access_enabled && var.allowed_client_ip != "" ? 1 : 0
  name             = "AllowCurrentClient"
  server_id        = azurerm_postgresql_flexible_server.lakehouse.id
  start_ip_address = var.allowed_client_ip
  end_ip_address   = var.allowed_client_ip
}

resource "azurerm_postgresql_flexible_server_database" "lakehouse" {
  name      = var.postgres_database_name
  server_id = azurerm_postgresql_flexible_server.lakehouse.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "mlflow" {
  name      = "mlflow"
  server_id = azurerm_postgresql_flexible_server.lakehouse.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_database" "airflow" {
  name      = "airflow"
  server_id = azurerm_postgresql_flexible_server.lakehouse.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_eventhub_namespace" "lakehouse" {
  name                = var.eventhub_namespace_name
  location            = azurerm_resource_group.lakehouse.location
  resource_group_name = azurerm_resource_group.lakehouse.name
  sku                 = "Standard"
  capacity            = 1

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_eventhub" "lakehouse" {
  name              = var.eventhub_name
  namespace_id      = azurerm_eventhub_namespace.lakehouse.id
  partition_count   = 2
  message_retention = 1
}

resource "azurerm_log_analytics_workspace" "lakehouse" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.lakehouse.location
  resource_group_name = azurerm_resource_group.lakehouse.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "lakehouse" {
  name                       = local.container_app_environment_name
  location                   = azurerm_resource_group.lakehouse.location
  resource_group_name        = azurerm_resource_group.lakehouse.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lakehouse.id
}

resource "azurerm_container_app" "unity_catalog" {
  name                         = "unity-catalog"
  container_app_environment_id = azurerm_container_app_environment.lakehouse.id
  resource_group_name          = azurerm_resource_group.lakehouse.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lakehouse.id]
  }

  registry {
    server   = azurerm_container_registry.lakehouse.login_server
    identity = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "postgres-admin-password"
    key_vault_secret_id = azurerm_key_vault_secret.postgres_admin_password.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "azure-sp-client-secret"
    key_vault_secret_id = azurerm_key_vault_secret.azure_sp_client_secret.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  template {
    container {
      name   = "unity-catalog"
      image  = local.unity_catalog_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "POSTGRES_HOST"
        value = azurerm_postgresql_flexible_server.lakehouse.fqdn
      }

      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }

      env {
        name  = "POSTGRES_USER"
        value = var.postgres_admin_username
      }

      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-admin-password"
      }

      env {
        name  = "POSTGRES_DB"
        value = var.postgres_database_name
      }

      env {
        name  = "AZURE_STORAGE_ACCOUNT_NAME"
        value = var.storage_account_name
      }

      env {
        name  = "AZURE_SP_CLIENT_ID"
        value = var.azure_sp_client_id
      }

      env {
        name        = "AZURE_SP_CLIENT_SECRET"
        secret_name = "azure-sp-client-secret"
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.azure_tenant_id
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_key_vault_access_policy.lakehouse_identity,
    azurerm_role_assignment.lakehouse_acr_pull,
  ]
}

resource "azurerm_container_app" "mlflow" {
  name                         = "mlflow"
  container_app_environment_id = azurerm_container_app_environment.lakehouse.id
  resource_group_name          = azurerm_resource_group.lakehouse.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lakehouse.id]
  }

  registry {
    server   = azurerm_container_registry.lakehouse.login_server
    identity = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "postgres-admin-password"
    key_vault_secret_id = azurerm_key_vault_secret.postgres_admin_password.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "storage-account-key"
    key_vault_secret_id = azurerm_key_vault_secret.storage_account_key.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  template {
    container {
      name   = "mlflow"
      image  = local.mlflow_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "POSTGRES_HOST"
        value = azurerm_postgresql_flexible_server.lakehouse.fqdn
      }

      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }

      env {
        name  = "POSTGRES_USER"
        value = var.postgres_admin_username
      }

      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-admin-password"
      }

      env {
        name  = "POSTGRES_DB"
        value = "mlflow"
      }

      env {
        name  = "MLFLOW_ARTIFACTS_DESTINATION"
        value = "wasbs://mlflow-artifacts@${var.storage_account_name}.blob.core.windows.net/mlflow-artifacts"
      }

      env {
        name  = "AZURE_STORAGE_ACCOUNT_NAME"
        value = var.storage_account_name
      }

      env {
        name        = "AZURE_STORAGE_ACCESS_KEY"
        secret_name = "storage-account-key"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 5000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_key_vault_access_policy.lakehouse_identity,
    azurerm_role_assignment.lakehouse_acr_pull,
  ]
}

resource "azurerm_container_app" "spark_connect" {
  name                         = "spark-connect"
  container_app_environment_id = azurerm_container_app_environment.lakehouse.id
  resource_group_name          = azurerm_resource_group.lakehouse.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lakehouse.id]
  }

  registry {
    server   = azurerm_container_registry.lakehouse.login_server
    identity = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "azure-sp-client-secret"
    key_vault_secret_id = azurerm_key_vault_secret.azure_sp_client_secret.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  template {
    container {
      name   = "spark-connect"
      image  = local.spark_connect_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "UNITY_CATALOG_URI"
        value = "https://${azurerm_container_app.unity_catalog.ingress[0].fqdn}"
      }

      env {
        name  = "AZURE_STORAGE_ACCOUNT_NAME"
        value = var.storage_account_name
      }

      env {
        name  = "AZURE_STORAGE_CONTAINER_NAME"
        value = var.storage_container_name
      }

      env {
        name  = "AZURE_SP_CLIENT_ID"
        value = var.azure_sp_client_id
      }

      env {
        name        = "AZURE_SP_CLIENT_SECRET"
        secret_name = "azure-sp-client-secret"
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.azure_tenant_id
      }

      env {
        name  = "SPARK_CONNECT_PORT"
        value = "15002"
      }
    }

    min_replicas = 1
    max_replicas = 1
  }

  ingress {
    external_enabled = true
    target_port      = 15002
    transport        = "http2"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_key_vault_access_policy.lakehouse_identity,
    azurerm_role_assignment.lakehouse_acr_pull,
    azurerm_container_app.unity_catalog,
  ]
}

resource "azurerm_container_app" "airflow" {
  name                         = "airflow"
  container_app_environment_id = azurerm_container_app_environment.lakehouse.id
  resource_group_name          = azurerm_resource_group.lakehouse.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.lakehouse.id]
  }

  registry {
    server   = azurerm_container_registry.lakehouse.login_server
    identity = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "postgres-admin-password"
    key_vault_secret_id = azurerm_key_vault_secret.postgres_admin_password.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  secret {
    name                = "airflow-admin-password"
    key_vault_secret_id = azurerm_key_vault_secret.airflow_admin_password.versionless_id
    identity            = azurerm_user_assigned_identity.lakehouse.id
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "airflow"
      image  = local.airflow_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "POSTGRES_HOST"
        value = azurerm_postgresql_flexible_server.lakehouse.fqdn
      }

      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }

      env {
        name  = "POSTGRES_USER"
        value = var.postgres_admin_username
      }

      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "postgres-admin-password"
      }

      env {
        name  = "POSTGRES_DB"
        value = "airflow"
      }

      env {
        name  = "AIRFLOW_ADMIN_USER"
        value = var.airflow_admin_username
      }

      env {
        name        = "AIRFLOW_ADMIN_PASSWORD"
        secret_name = "airflow-admin-password"
      }

      env {
        name  = "KAFKA_BOOTSTRAP_SERVERS"
        value = "${azurerm_eventhub_namespace.lakehouse.name}.servicebus.windows.net:9093"
      }

      env {
        name  = "SPARK_CONNECT_URL"
        value = "sc://${azurerm_container_app.spark_connect.ingress[0].fqdn}:443/;use_ssl=true"
      }

      env {
        name  = "UNITY_CATALOG_URL"
        value = "https://${azurerm_container_app.unity_catalog.ingress[0].fqdn}"
      }

      env {
        name  = "MLFLOW_TRACKING_URI"
        value = "https://${azurerm_container_app.mlflow.ingress[0].fqdn}"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8085

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_key_vault_access_policy.lakehouse_identity,
    azurerm_role_assignment.lakehouse_acr_pull,
    azurerm_container_app.spark_connect,
  ]
}
