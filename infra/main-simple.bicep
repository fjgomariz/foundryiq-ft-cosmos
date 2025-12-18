@description('Project name for resource naming')
param projectName string = 'fiqftcosmos'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name for the Cosmos Account')
param cosmosDbAccountName string = '${projectName}-cdb'

@description('Name for the Storage Account')
param storageAccountName string = toLower('${projectName}sta')

@description('Name for the web app hosting the MCP')
param webAppName string = '${projectName}-mcpapi'

// @description('Display name for the Entra App')
// param entraAppDisplayName string = 'Azure Cosmos DB MCP Toolkit API'


@description('Common tags for all resources')
param commonTags object = {
  Application: 'Foundry-ft-Cosmos'
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  identity: {
    type: 'None'
  }
  tags: commonTags
  properties: {
    publicNetworkAccess: 'Enabled'
    enableMultipleWriteLocations: false
    databaseAccountOfferType: 'Standard'
    capacityMode: 'Provisioned'
    disableLocalAuth: true
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capacity: {
      totalThroughputLimit: 4000
    }
  }

    resource cosmosDbAccountDatabase 'sqlDatabases@2025-05-01-preview' = {
      name: 'customers'
      properties: {
        resource: {
          id: 'customers'
        }
      }

        resource customerSpentCotnainer 'containers@2025-05-01-preview' = {
          name: 'customer_spent'
          properties: {
            resource: {
              id: 'customer_spent'
              partitionKey: {
                paths: [
                  '/customerId'
                ]
                kind: 'Hash'
                version: 2
            }
          }
        }
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: commonTags
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }

  resource blobService 'blobServices@2025-01-01' = {
    name: 'default'

      resource customerInfoContainer 'containers@2025-01-01' = {
        name: 'customer-info'
        properties: {
          publicAccess: 'None'
        }
      }
    }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${projectName}-asp'
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    capacity: 1
  }
  tags: commonTags
  properties: {
    reserved: false
    perSiteScaling: false
    maximumElasticWorkerCount: 1
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  tags: commonTags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    reserved: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'DOTNETCORE|10.0'
      appSettings: [
      ]
    }
  }
}



// Outputs for azd and other consumers
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId

// Infrastructure outputs
output RESOURCE_GROUP_NAME string = resourceGroup().name
output APP_SERVICE_IDENTITY_PRINCIPAL_ID string = webApp.identity.principalId
