output "service_url" {
  description = "Public HTTPS URL of the Azure Container App URL shortener service"
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "acr_name" {
  description = "Azure Container Registry name for az acr build"
  value       = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  description = "Azure Container Registry login server"
  value       = azurerm_container_registry.acr.login_server
}

output "cosmos_endpoint" {
  description = "Azure Cosmos DB Serverless account endpoint"
  value       = azurerm_cosmosdb_account.db.endpoint
}

output "log_analytics_workspace_id" {
  description = "Azure Log Analytics Workspace resource ID"
  value       = azurerm_log_analytics_workspace.logs.id
}
