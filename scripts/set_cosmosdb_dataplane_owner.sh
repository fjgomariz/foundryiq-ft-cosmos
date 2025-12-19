#!/bin/bash

###############################################################################
# Script: Grant Cosmos DB Data Plane Owner Role to Application Identity
# Description: Assigns Azure Cosmos DB for NoSQL data plane permissions to 
#              an application identity using role-based access control (RBAC).
# Based on: https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/how-to-connect-role-based-access-control?pivots=azure-cli
###############################################################################

set -e  # Exit on error

# Parameters
PRINCIPAL_ID="${1}"
RESOURCE_GROUP="${2}"
COSMOS_ACCOUNT="${3}"

# Validate parameters
if [ -z "$PRINCIPAL_ID" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$COSMOS_ACCOUNT" ]; then
    echo "Usage: $0 <PRINCIPAL_ID> <RESOURCE_GROUP> <COSMOS_ACCOUNT>"
    echo ""
    echo "Parameters:"
    echo "  PRINCIPAL_ID    - The application/managed identity principal ID (object ID)"
    echo "  RESOURCE_GROUP  - The name of the resource group containing the Cosmos DB account"
    echo "  COSMOS_ACCOUNT  - The name of the Cosmos DB account"
    echo ""
    echo "Example:"
    echo "  $0 aaaaaaaa-bbbb-cccc-1111-222222222222 rg-myapp cosmosdb-myapp"
    exit 1
fi

echo "================================================"
echo "Cosmos DB Data Plane RBAC Configuration"
echo "================================================"
echo "Principal ID:     $PRINCIPAL_ID"
echo "Resource Group:   $RESOURCE_GROUP"
echo "Cosmos Account:   $COSMOS_ACCOUNT"
echo "================================================"
echo ""

# Step 1: Check if role definition already exists
echo "[1/3] Checking for existing 'Data Plane Owner' role definition..."

EXISTING_ROLE=$(az cosmosdb sql role definition list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$COSMOS_ACCOUNT" \
    --query "[?roleName=='Azure Cosmos DB for NoSQL Data Plane Owner'].id" \
    -o tsv)

if [ -n "$EXISTING_ROLE" ]; then
    echo "✓ Found existing role definition: $EXISTING_ROLE"
    ROLE_DEFINITION_ID="$EXISTING_ROLE"
else
    echo "Creating new 'Data Plane Owner' role definition..."
    
    # Create temporary JSON file for role definition
    ROLE_DEF_FILE=$(mktemp)
    cat > "$ROLE_DEF_FILE" <<EOF
{
  "RoleName": "Azure Cosmos DB for NoSQL Data Plane Owner",
  "Type": "CustomRole",
  "AssignableScopes": [
    "/"
  ],
  "Permissions": [
    {
      "DataActions": [
        "Microsoft.DocumentDB/databaseAccounts/readMetadata",
        "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*",
        "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*"
      ]
    }
  ]
}
EOF

    # Create the role definition
    ROLE_OUTPUT=$(az cosmosdb sql role definition create \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$COSMOS_ACCOUNT" \
        --body "@$ROLE_DEF_FILE")
    
    ROLE_DEFINITION_ID=$(echo "$ROLE_OUTPUT" | jq -r '.id')
    echo "✓ Created role definition: $ROLE_DEFINITION_ID"
    
    # Clean up temp file
    rm -f "$ROLE_DEF_FILE"
fi

# Extract just the GUID from the full role definition ID
ROLE_DEFINITION_GUID=$(basename "$ROLE_DEFINITION_ID")

echo ""

# Step 2: Get the account scope
echo "[2/3] Getting Cosmos DB account scope..."

ACCOUNT_SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DocumentDB/databaseAccounts/$COSMOS_ACCOUNT"
echo "✓ Account scope: $ACCOUNT_SCOPE"

echo ""

# Step 3: Check if role assignment already exists
echo "[3/3] Checking for existing role assignments..."

EXISTING_ASSIGNMENT=$(az cosmosdb sql role assignment list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$COSMOS_ACCOUNT" \
    --query "[?principalId=='$PRINCIPAL_ID' && roleDefinitionId=='$ROLE_DEFINITION_ID'].id" \
    -o tsv)

if [ -n "$EXISTING_ASSIGNMENT" ]; then
    echo "✓ Role assignment already exists: $EXISTING_ASSIGNMENT"
else
    echo "Creating role assignment..."
    
    az cosmosdb sql role assignment create \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$COSMOS_ACCOUNT" \
        --role-definition-id "$ROLE_DEFINITION_GUID" \
        --principal-id "$PRINCIPAL_ID" \
        --scope "$ACCOUNT_SCOPE"
    
    echo "✓ Role assignment created successfully"
fi

echo ""
echo "================================================"
echo "✓ Configuration completed successfully!"
echo "================================================"
echo ""
echo "The identity '$PRINCIPAL_ID' now has data plane access to:"
echo "  - Read account metadata"
echo "  - Manage containers in all databases"
echo "  - Create, read, update, delete items in all containers"
echo ""
echo "Scope: All databases and containers in '$COSMOS_ACCOUNT'"
echo "================================================"
