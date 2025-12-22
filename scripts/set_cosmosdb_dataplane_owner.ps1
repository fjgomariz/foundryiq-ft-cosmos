#!/usr/bin/env pwsh

###############################################################################
# Script: Grant Cosmos DB Data Plane Owner Role to Application Identity
# Description: Assigns Azure Cosmos DB for NoSQL data plane permissions to 
#              an application identity using role-based access control (RBAC).
# Based on: https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/how-to-connect-role-based-access-control?pivots=azure-cli
###############################################################################

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$PrincipalId,
    
    [Parameter(Mandatory=$true, Position=1)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true, Position=2)]
    [string]$CosmosAccount
)

$ErrorActionPreference = "Stop"

# Validate parameters
if ([string]::IsNullOrWhiteSpace($PrincipalId) -or 
    [string]::IsNullOrWhiteSpace($ResourceGroup) -or 
    [string]::IsNullOrWhiteSpace($CosmosAccount)) {
    
    Write-Host "Usage: .\set_cosmosdb_dataplane_owner.ps1 <PRINCIPAL_ID> <RESOURCE_GROUP> <COSMOS_ACCOUNT>"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  PRINCIPAL_ID    - The application/managed identity principal ID (object ID)"
    Write-Host "  RESOURCE_GROUP  - The name of the resource group containing the Cosmos DB account"
    Write-Host "  COSMOS_ACCOUNT  - The name of the Cosmos DB account"
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  .\set_cosmosdb_dataplane_owner.ps1 aaaaaaaa-bbbb-cccc-1111-222222222222 rg-myapp cosmosdb-myapp"
    exit 1
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Cosmos DB Data Plane RBAC Configuration" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Principal ID:     $PrincipalId"
Write-Host "Resource Group:   $ResourceGroup"
Write-Host "Cosmos Account:   $CosmosAccount"
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if role definition already exists
Write-Host "[1/3] Checking for existing 'Data Plane Owner' role definition..." -ForegroundColor Yellow

$roleDefinitionId = az cosmosdb sql role definition list `
    --resource-group $ResourceGroup `
    --account-name $CosmosAccount `
    --query "[?roleName=='Azure Cosmos DB for NoSQL Data Plane Owner'].id" `
    -o tsv

if ($roleDefinitionId) {
    Write-Host "✓ Found existing role definition: $roleDefinitionId" -ForegroundColor Green
} else {
    Write-Host "Creating new 'Data Plane Owner' role definition..."
    
    # Create role definition JSON
    $roleDefinition = @{
        RoleName = "Azure Cosmos DB for NoSQL Data Plane Owner"
        Type = "CustomRole"
        AssignableScopes = @("/")
        Permissions = @(
            @{
                DataActions = @(
                    "Microsoft.DocumentDB/databaseAccounts/readMetadata",
                    "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*",
                    "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*"
                )
            }
        )
    }
    
    # Create temporary JSON file
    $tempFile = [System.IO.Path]::GetTempFileName()
    $jsonFile = $tempFile -replace '\.tmp$', '.json'
    Move-Item $tempFile $jsonFile -Force
    
    $roleDefinition | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding utf8
    
    # Create the role definition
    $roleOutputJson = az cosmosdb sql role definition create `
        --resource-group $ResourceGroup `
        --account-name $CosmosAccount `
        --body "@$jsonFile"
    
    $roleOutput = $roleOutputJson | ConvertFrom-Json
    $roleDefinitionId = $roleOutput.id
    Write-Host "✓ Created role definition: $roleDefinitionId" -ForegroundColor Green
    
    # Clean up temp file
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

# Extract just the GUID from the full role definition ID
$roleDefinitionGuid = Split-Path $roleDefinitionId -Leaf

Write-Host ""

# Step 2: Get the account scope
Write-Host "[2/3] Getting Cosmos DB account scope..." -ForegroundColor Yellow

$subscriptionId = (az account show --query id -o tsv)
$accountScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$CosmosAccount"
Write-Host "✓ Account scope: $accountScope" -ForegroundColor Green

Write-Host ""

# Step 3: Check if role assignment already exists
Write-Host "[3/3] Checking for existing role assignments..." -ForegroundColor Yellow

$existingAssignment = az cosmosdb sql role assignment list `
    --resource-group $ResourceGroup `
    --account-name $CosmosAccount `
    --query "[?principalId=='$PrincipalId' && roleDefinitionId=='$roleDefinitionId'].id" `
    -o tsv

if ($existingAssignment) {
    Write-Host "✓ Role assignment already exists: $existingAssignment" -ForegroundColor Green
} else {
    Write-Host "Creating role assignment..."
    
    az cosmosdb sql role assignment create `
        --resource-group $ResourceGroup `
        --account-name $CosmosAccount `
        --role-definition-id $roleDefinitionGuid `
        --principal-id $PrincipalId `
        --scope $accountScope
    
    Write-Host "✓ Role assignment created successfully" -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "✓ Configuration completed successfully!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The identity '$PrincipalId' now has data plane access to:"
Write-Host "  - Read account metadata"
Write-Host "  - Manage containers in all databases"
Write-Host "  - Create, read, update, delete items in all containers"
Write-Host ""
Write-Host "Scope: All databases and containers in '$CosmosAccount'"
Write-Host "================================================" -ForegroundColor Cyan
