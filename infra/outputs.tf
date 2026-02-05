output "AZURE_LOCATION" {
  value       = var.location
  description = "Azure location"
}

output "AZURE_TENANT_ID" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Azure tenant ID"
}

output "AZURE_SUBSCRIPTION_ID" {
  value       = data.azurerm_client_config.current.subscription_id
  description = "Azure subscription ID"
}

output "RESOURCE_GROUP_NAME" {
  value       = data.azurerm_resource_group.main.name
  description = "Resource group name"
}

output "APP_SERVICE_IDENTITY_PRINCIPAL_ID" {
  value       = azurerm_linux_web_app.main.identity[0].principal_id
  description = "App Service system-assigned managed identity principal ID"
}

output "APPLICATION_INSIGHTS_CONNECTION_STRING" {
  value       = azurerm_application_insights.main.connection_string
  description = "Application Insights connection string"
  sensitive   = true
}

output "COSMOS_DB_ENDPOINT" {
  value       = azurerm_cosmosdb_account.main.endpoint
  description = "Cosmos DB endpoint"
}

output "WEB_APP_NAME" {
  value       = azurerm_linux_web_app.main.name
  description = "Web app name"
}
