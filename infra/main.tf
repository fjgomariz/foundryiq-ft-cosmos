# Data sources
data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Cosmos DB Account
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.project_name}-cdb"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capacity {
    total_throughput_limit = 4000
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }

  public_network_access_enabled    = true
  multiple_write_locations_enabled = false
  local_authentication_disabled    = true

  tags = var.common_tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "customers" {
  name                = "customers"
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB SQL Container
resource "azurerm_cosmosdb_sql_container" "customer_spent" {
  name                  = "customer_spent"
  resource_group_name   = data.azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.customers.name
  partition_key_paths   = ["/customerId"]
  partition_key_version = 2
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                            = lower("${var.project_name}sta")
  resource_group_name             = data.azurerm_resource_group.main.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  tags = var.common_tags
}

# Blob Service for Storage Account
resource "azurerm_storage_container" "customer_info" {
  name                  = "customer-info"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "${var.project_name}-asp"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "B1"

  tags = var.common_tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-law"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.common_tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-appi"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = 90

  tags = var.common_tags
}

# Linux Web App
resource "azurerm_linux_web_app" "main" {
  name                = "${var.project_name}-mcpapi"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  site_config {
    always_on = false
    application_stack {
      dotnet_version = "10.0"
    }

    app_command_line = ""
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "COSMOS_ENDPOINT"                       = azurerm_cosmosdb_account.main.endpoint
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }

  tags = var.common_tags
}

# User Assigned Managed Identity for Search
resource "azurerm_user_assigned_identity" "search" {
  name                = "${var.project_name}-ais-umi"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = var.common_tags
}

# Azure AI Search Service
resource "azurerm_search_service" "main" {
  name                          = "${var.project_name}-ais"
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.main.name
  sku                           = "standard"
  replica_count                 = 1
  partition_count               = 1
  public_network_access_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.search.id]
  }

  tags = var.common_tags
}

# Storage Blob Data Contributor role for Search Managed Identity
resource "azurerm_role_assignment" "search_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.search.principal_id
}

# Storage Table Data Contributor role for Search Managed Identity
resource "azurerm_role_assignment" "search_storage_table" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.search.principal_id
}

# User Assigned Managed Identity for Foundry
resource "azurerm_user_assigned_identity" "foundry" {
  name                = "${var.project_name}-foundry-umi"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = var.common_tags
}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                = "${var.project_name}-kv"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  rbac_authorization_enabled      = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  public_network_access_enabled   = true

  tags = var.common_tags
}

# Key Vault Contributor role for Foundry Managed Identity
resource "azurerm_role_assignment" "foundry_keyvault_contributor" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
}

# Key Vault Secrets Officer role for Foundry Managed Identity
resource "azurerm_role_assignment" "foundry_keyvault_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.foundry.principal_id
}

# Cognitive Services Account (Foundry)
resource "azurerm_cognitive_account" "foundry" {
  name                  = "${var.project_name}-foundry"
  location              = var.location
  resource_group_name   = data.azurerm_resource_group.main.name
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = "${var.project_name}-foundry"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.foundry.id]
  }

  public_network_access_enabled = true
  local_auth_enabled            = false

  tags = var.common_tags
}

# Azure AI User role for Search Managed Identity on Foundry
resource "azurerm_role_assignment" "search_foundry_ai_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Azure AI User"
  principal_id         = azurerm_user_assigned_identity.search.principal_id
}

# Cognitive Services OpenAI User role for Search Managed Identity on Foundry
resource "azurerm_role_assignment" "search_foundry_openai_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.search.principal_id
}

# Cognitive Services User role for Search Managed Identity on Foundry
resource "azurerm_role_assignment" "search_foundry_cognitive_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.search.principal_id
}
