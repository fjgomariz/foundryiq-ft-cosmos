#!/usr/bin/env bash

###############################################################################
# Script: Grant Cosmos DB Data Plane Owner Role to Application Identity
# Description: Assigns Azure Cosmos DB for NoSQL data plane permissions to 
#              an application identity using role-based access control (RBAC).
# Based on: https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/how-to-connect-role-based-access-control?pivots=azure-cli
###############################################################################

set -euo pipefail

# Cleanup function for temporary files
TEMP_FILE=""
cleanup() {
    if [[ -n "${TEMP_FILE}" ]] && [[ -f "${TEMP_FILE}" ]]; then
        rm -f "${TEMP_FILE}"
    fi
}
trap cleanup EXIT

# Function to print usage information
print_usage() {
    echo "Usage: ./set-cosmosdb-dataplane-owner.sh <PRINCIPAL_ID> <RESOURCE_GROUP> <COSMOS_ACCOUNT>"
    echo ""
    echo "Parameters:"
    echo "  PRINCIPAL_ID    - The application/managed identity principal ID (object ID)"
    echo "  RESOURCE_GROUP  - The name of the resource group containing the Cosmos DB account"
    echo "  COSMOS_ACCOUNT  - The name of the Cosmos DB account"
    echo ""
    echo "Example:"
    echo "  ./set-cosmosdb-dataplane-owner.sh aaaaaaaa-bbbb-cccc-1111-222222222222 rg-myapp cosmosdb-myapp"
}

# Validate parameters
if [[ $# -ne 3 ]]; then
    print_usage
    exit 1
fi

PRINCIPAL_ID="$1"
RESOURCE_GROUP="$2"
COSMOS_ACCOUNT="$3"

# Validate that parameters are not empty
if [[ -z "${PRINCIPAL_ID}" ]] || [[ -z "${RESOURCE_GROUP}" ]] || [[ -z "${COSMOS_ACCOUNT}" ]]; then
    print_usage
    exit 1
fi

# Print header
echo "================================================"
echo "Cosmos DB Data Plane RBAC Configuration"
echo "================================================"
echo "Principal ID:     ${PRINCIPAL_ID}"
echo "Resource Group:   ${RESOURCE_GROUP}"
echo "Cosmos Account:   ${COSMOS_ACCOUNT}"
echo "================================================"
echo ""

# Step 1: Check if role definition already exists
echo "[1/3] Checking for existing 'Data Plane Owner' role definition..."

ROLE_DEFINITION_ID=$(az cosmosdb sql role definition list \
    --resource-group "${RESOURCE_GROUP}" \
    --account-name "${COSMOS_ACCOUNT}" \
    --query "[?roleName=='Azure Cosmos DB for NoSQL Data Plane Owner'].id" \
    -o tsv || echo "")

if [[ -n "${ROLE_DEFINITION_ID}" ]]; then
    echo "✓ Found existing role definition: ${ROLE_DEFINITION_ID}"
else
    echo "Creating new 'Data Plane Owner' role definition..."
    
    # Create temporary JSON file for role definition
    TEMP_FILE=$(mktemp)
    
    # Write role definition to temp file
    cat > "${TEMP_FILE}" << 'EOF'
{
  "RoleName": "Azure Cosmos DB for NoSQL Data Plane Owner",
  "Type": "CustomRole",
  "AssignableScopes": ["/"],
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
    
    # Create the role definition and extract ID using Azure CLI query
    ROLE_DEFINITION_ID=$(az cosmosdb sql role definition create \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${COSMOS_ACCOUNT}" \
        --body "@${TEMP_FILE}" \
        --query "id" -o tsv)
    
    if [[ -z "${ROLE_DEFINITION_ID}" ]]; then
        echo "Error: Failed to create role definition or extract role definition ID" >&2
        exit 1
    fi
    
    echo "✓ Created role definition: ${ROLE_DEFINITION_ID}"
fi

# Extract just the GUID from the full role definition ID (last path segment)
ROLE_DEFINITION_GUID=$(basename "${ROLE_DEFINITION_ID}")

# Validate that GUID extraction was successful
if [[ -z "${ROLE_DEFINITION_GUID}" ]]; then
    echo "Error: Failed to extract role definition GUID from: ${ROLE_DEFINITION_ID}" >&2
    exit 1
fi

echo ""

# Step 2: Get the account scope
echo "[2/3] Getting Cosmos DB account scope..."

SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")

if [[ -z "${SUBSCRIPTION_ID}" ]]; then
    echo "Error: Failed to get subscription ID. Please ensure you are logged in to Azure CLI." >&2
    echo "Run 'az login' to authenticate." >&2
    exit 1
fi

ACCOUNT_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOS_ACCOUNT}"

echo "✓ Account scope: ${ACCOUNT_SCOPE}"

echo ""

# Step 3: Check if role assignment already exists
echo "[3/3] Checking for existing role assignments..."

EXISTING_ASSIGNMENT=$(az cosmosdb sql role assignment list \
    --resource-group "${RESOURCE_GROUP}" \
    --account-name "${COSMOS_ACCOUNT}" \
    --query "[?principalId=='${PRINCIPAL_ID}' && roleDefinitionId=='${ROLE_DEFINITION_ID}'].id" \
    -o tsv || echo "")

if [[ -n "${EXISTING_ASSIGNMENT}" ]]; then
    echo "✓ Role assignment already exists: ${EXISTING_ASSIGNMENT}"
else
    echo "Creating role assignment..."
    
    az cosmosdb sql role assignment create \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${COSMOS_ACCOUNT}" \
        --role-definition-id "${ROLE_DEFINITION_GUID}" \
        --principal-id "${PRINCIPAL_ID}" \
        --scope "${ACCOUNT_SCOPE}"
    
    echo "✓ Role assignment created successfully"
fi

echo ""
echo "================================================"
echo "✓ Configuration completed successfully!"
echo "================================================"
echo ""
echo "The identity '${PRINCIPAL_ID}' now has data plane access to:"
echo "  - Read account metadata"
echo "  - Manage containers in all databases"
echo "  - Create, read, update, delete items in all containers"
echo ""
echo "Scope: All databases and containers in '${COSMOS_ACCOUNT}'"
echo "================================================"
