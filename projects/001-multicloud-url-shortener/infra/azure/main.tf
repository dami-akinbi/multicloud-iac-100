resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  use_custom_image = var.image_tag != ""
  effective_image  = local.use_custom_image ? "${azurerm_container_registry.acr.login_server}/${var.image_tag}" : "mcr.microsoft.com/k8se/quickstart:latest"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.app_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${var.app_name}${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "law-${var.app_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${var.app_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "cosmos-${var.app_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  free_tier_enabled   = false

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "shortenerdb"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.db.name
}

resource "azurerm_cosmosdb_sql_container" "urls" {
  name                = "urls"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.db.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_paths = ["/id"]
}

resource "azurerm_cosmosdb_sql_role_assignment" "app_data_contributor" {
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.db.name
  role_definition_id  = "${azurerm_cosmosdb_account.db.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.app.principal_id
  scope               = azurerm_cosmosdb_account.db.id
}

resource "azurerm_container_app" "app" {
  name                         = "ca-${var.app_name}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = local.use_custom_image ? 8080 : 80

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 3

    container {
      name   = "url-shortener"
      image  = local.effective_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "CLOUD_PROVIDER"
        value = "azure"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app.client_id
      }
      env {
        name  = "AZURE_COSMOS_ENDPOINT"
        value = azurerm_cosmosdb_account.db.endpoint
      }
      env {
        name  = "AZURE_COSMOS_DATABASE"
        value = azurerm_cosmosdb_sql_database.db.name
      }
      env {
        name  = "AZURE_COSMOS_CONTAINER"
        value = azurerm_cosmosdb_sql_container.urls.name
      }
      env {
        name  = "AZURE_REGION"
        value = var.location
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_cosmosdb_sql_role_assignment.app_data_contributor,
  ]
}
