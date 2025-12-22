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
    reserved: true
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
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
  }
}

resource searchUserAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: '${projectName}-ais-umi'
  location: location
  tags: commonTags
}

resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: '${projectName}-ais'
  location: location
  sku: {
    name: 'standard'
  }
  identity: {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${searchUserAssignedIdentity.id}': {}
      }
    }
  tags: commonTags
  properties: {
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'Enabled'
  }
}

resource storageBlobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}

// Storage Blob Data Contributor role assignment for user-assigned managed identity
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, searchUserAssignedIdentity.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinition.id
    principalId: searchUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageTableDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
}


// Storage Table Data Contributor role assignment for user-assigned managed identity
resource storageTableDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, searchUserAssignedIdentity.id, 'StorageTableDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: storageTableDataContributorRoleDefinition.id
    principalId: searchUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource azureAIUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}

// Azure AI User role assignment for user-assigned managed identity
resource azureAIUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchUserAssignedIdentity.id, 'AzureAIUser')
  scope: foundry
  properties: {
    roleDefinitionId: azureAIUserRoleDefinition.id
    principalId: searchUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServicesOpenAIUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
}

// Cognitive Services OpenAI User role assignment for user-assigned managed identity
resource cognitiveServicesOpenAIUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchUserAssignedIdentity.id, 'CognitiveServicesOpenAIUser')
  scope: foundry
  properties: {
    roleDefinitionId: cognitiveServicesOpenAIUserRoleDefinition.id
    principalId: searchUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServicesUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'a97b65f3-24c7-4388-baec-2e87135dc908'
}

// Cognitive Services User role assignment for user-assigned managed identity
resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, searchUserAssignedIdentity.id, 'CognitiveServicesUser')
  scope: foundry
  properties: {
    roleDefinitionId: cognitiveServicesUserRoleDefinition.id
    principalId: searchUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: '${projectName}-kv'
  location: location
  tags: commonTags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    accessPolicies: []
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
}

resource foundryUserAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: '${projectName}-foundry-umi'
  location: location
  tags: commonTags
}

resource keyVaultContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: keyVault
  name: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
}

resource keyVaultSecretsOfficerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: keyVault
  name: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

// Key Vault Contributor role assignment for user-assigned managed identity
resource keyVaultContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, foundryUserAssignedIdentity.id, 'KeyVaultContributor')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultContributorRoleDefinition.id
    principalId: foundryUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets Officer role assignment for user-assigned managed identity
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, foundryUserAssignedIdentity.id, 'KeyVaultSecretsOfficer')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleDefinition.id
    principalId: foundryUserAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: '${projectName}-foundry'
  location: location
  kind: 'AIServices'
  identity: {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${foundryUserAssignedIdentity.id}': {}
      }
    }
  tags: commonTags
  properties: {
    apiProperties: {}
    customSubDomainName: '${projectName}-foundry'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    allowProjectManagement: true
    defaultProject: projectName
    associatedProjects: [
      projectName
    ]
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
  sku: {
    name: 'S0'
  }

    resource storageConnection 'connections@2025-06-01' = {
      name: 'storageConnection'
      properties: {
        authType: 'AAD'
        category: 'AzureStorageAccount'
        target: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/'
        useWorkspaceManagedIdentity: false
        isSharedToAll: false
        sharedUserList: []
        peRequirement: 'NotRequired'
        peStatus: 'NotApplicable'
        metadata: {
          ApiType: 'Azure'
          ResourceId: storageAccount.id
        }
      }
    }

    resource foundryProject 'projects@2025-06-01' = {
      name: projectName
      location: location
      identity: {
        type: 'SystemAssigned'
      }
      properties: {
        description: 'Foundry ft Cosmos project'
        displayName: 'Foundry ft Cosmos'
      }

      resource projectStorageConnection 'connections@2025-06-01' = {
        name: 'projectStorageConnection'
        properties: {
          authType: 'AAD'
          category: 'AzureStorageAccount'
          target: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/'
          useWorkspaceManagedIdentity: true
          isSharedToAll: false
          sharedUserList: []
          peRequirement: 'NotRequired'
          peStatus: 'NotApplicable'
          metadata: {
            ApiType: 'Azure'
            ResourceId: storageAccount.id
          }
        }
      }
    }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: '${projectName}-law'
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource applicationInsights 'microsoft.insights/components@2020-02-02' = {
  name: '${projectName}-appi'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}



// Outputs for azd and other consumers
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId

// Infrastructure outputs
output RESOURCE_GROUP_NAME string = resourceGroup().name
output APP_SERVICE_IDENTITY_PRINCIPAL_ID string = webApp.identity.principalId
output APPLICATION_INSIGHTS_CONNECTION_STRING string = applicationInsights.properties.ConnectionString
output COSMOS_DB_ENDPOINT string = cosmosDbAccount.properties.documentEndpoint
output WEB_APP_NAME string = webApp.name
