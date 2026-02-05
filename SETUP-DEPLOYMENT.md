# Azure Federated Credentials Setup for GitHub Actions

This guide walks you through setting up **federated credentials (OIDC)** to allow GitHub Actions to deploy to Azure without storing secrets.

---

## Part 1: Azure Configuration

### Step 1: Create an App Registration

```bash
# Login to Azure
az login

# Create the app registration
az ad app create --display-name "GitHub-FoundryIQ-FT-Cosmos-Deploy"
```

Note the **Application (client) ID** from the output.

### Step 2: Create a Service Principal

```bash
# Replace <APP_ID> with the Application ID from Step 1
az ad sp create --id <APP_ID>
```

Note the **Object ID** of the service principal from the output.

### Step 3: Assign Azure Permissions

Grant the service principal **Contributor** access to your resource group:

```bash
# Replace <SUBSCRIPTION_ID> and <RESOURCE_GROUP_NAME>
az role assignment create \
  --assignee <APP_ID> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP_NAME>
```

### Step 4: Configure Federated Credentials

Add a federated credential for GitHub Actions:

```bash
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "GitHub-Actions-Main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_GITHUB_ORG>/<YOUR_GITHUB_REPO>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Replace**:
- `<YOUR_GITHUB_ORG>` - Your GitHub organization or username
- `<YOUR_GITHUB_REPO>` - Your repository name (e.g., `foundryiq-ft-cosmos`)

**Example**:
```bash
"subject": "repo:myorg/foundryiq-ft-cosmos:ref:refs/heads/main"
```

### Step 5: Get Your Tenant ID

```bash
az account show --query tenantId -o tsv
```

---

## Part 2: GitHub Configuration

### Step 1: Add Secrets

Go to your GitHub repository:
1. Navigate to **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** and add these **3 secrets**:

| Secret Name | Value | Where to Find |
|------------|-------|---------------|
| `AZURE_CLIENT_ID` | Application (client) ID | From Azure App Registration (Step 1) |
| `AZURE_TENANT_ID` | Tenant ID | From `az account show` (Step 5) |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | From Azure portal or `az account show` |

### Step 2: Add Variables

In the same **Settings** → **Secrets and variables** → **Actions** page:
1. Click the **Variables** tab
2. Click **New repository variable** and add these **3 variables**:

| Variable Name | Value | Example |
|--------------|-------|---------|
| `PROJECT_NAME` | Unique project identifier (lowercase, no spaces) | `fiqftcosmos` |
| `AZURE_RESOURCE_GROUP` | Your resource group name | `rg-foundryiq-ft-cosmos` |
| `AZURE_LOCATION` | Azure region | `eastus` |

**Important**: `PROJECT_NAME` is used to generate resource names (e.g., `{PROJECT_NAME}-cdb` for Cosmos DB, `{PROJECT_NAME}-mcpapi` for Web App). Keep it short and unique to avoid Azure naming conflicts.

---

## Part 3: Deployment Workflows

This repository has two automated deployment workflows:

### 1. Infrastructure Deployment (`deploy-infra.yaml`)

**Technology**: Terraform

**Triggers**: 
- Push to `main` branch with changes in `infra/**`
- Manual trigger via workflow_dispatch

**What it deploys**:
- Cosmos DB account and database
- Storage account with blob container
- Azure Web App (Linux, .NET 10)
- Azure AI Search with user-assigned managed identity
- Key Vault
- Application Insights
- User-assigned managed identities for services
- Role assignments for RBAC permissions

**Outputs**: Cosmos DB endpoint, Application Insights connection string, web app name

**Process**:
1. Checks out code
2. Sets up Terraform
3. Authenticates to Azure via OIDC
4. Runs `terraform init`
5. Runs `terraform plan` with variables
6. Runs `terraform apply`
7. Exports outputs for downstream workflows

### 2. MCP API Deployment (`deploy-mcp.yaml`)

**Triggers**: 
- Push to `main` branch with changes in `src/Customers.MCP/**`
- Manual trigger via workflow_dispatch

**What it does**:
- Builds .NET 10 application in Release mode
- Retrieves infrastructure outputs (Cosmos DB endpoint, App Insights connection string)
- Configures app settings automatically
- Deploys to `{PROJECT_NAME}-mcpapi` Web App

**Configuration Set**:
- `CosmosDb__Endpoint`: Retrieved from infrastructure deployment
- `APPLICATIONINSIGHTS_CONNECTION_STRING`: Retrieved from infrastructure deployment

### Deployment Order

**First-time setup**:
1. Run infrastructure deployment (creates all Azure resources)
2. Run MCP API deployment (deploys application)

**Subsequent updates**:
- Changes to `infra/**` → Infrastructure workflow runs automatically
- Changes to `src/Customers.MCP/**` → MCP API workflow runs automatically

---

## Part 4: Verify Setup

### Test Infrastructure Deployment

You can manually trigger the workflow:
1. Go to **Actions** tab in GitHub
2. Select **Deploy Infrastructure**
3. Click **Run workflow** → **Run workflow**

Or push a change to the `infra/` folder on the `main` branch.

### Test MCP API Deployment

After infrastructure is deployed:
1. Go to **Actions** tab in GitHub
2. Select **Deploy MCP API**
3. Click **Run workflow** → **Run workflow**

Or push a change to the `src/Customers.MCP/` folder on the `main` branch.

### Troubleshooting

**Error: "No subscription found"**
- Verify `AZURE_SUBSCRIPTION_ID` is correct
- Check service principal has access to the subscription

**Error: "AADSTS70021: No matching federated identity"**
- Verify the `subject` in federated credential matches your repo exactly
- Format: `repo:OWNER/REPO:ref:refs/heads/main`

**Error: "Authorization failed"**
- Ensure service principal has Contributor role on resource group
- Check role assignment: `az role assignment list --assignee <APP_ID>`

**Error: "No deployment found" (MCP API workflow)**
- Ensure infrastructure has been deployed first
- The MCP API workflow retrieves outputs from the latest `infra-*` deployment

**Error: "Web app not found"**
- Verify `PROJECT_NAME` variable matches the name used in infrastructure deployment
- Web app name format: `{PROJECT_NAME}-mcpapi`

---

## Part 5: Application Configuration

The MCP API deployment automatically configures these settings:

| Setting | Source | Purpose |
|---------|--------|---------|
| `CosmosDb__Endpoint` | Infrastructure output | Cosmos DB connection endpoint |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Infrastructure output | Application monitoring |

### Additional Settings

To add more app settings, update the "Configure App Settings" step in [.github/workflows/deploy-mcp.yaml](.github/workflows/deploy-mcp.yaml):

```yaml
- name: Configure App Settings
  run: |
    az webapp config appsettings set \
      --resource-group ${{ vars.AZURE_RESOURCE_GROUP }} \
      --name ${{ vars.PROJECT_NAME }}-mcpapi \
      --settings \
        CosmosDb__Endpoint="${{ steps.infra.outputs.cosmos-endpoint }}" \
        APPLICATIONINSIGHTS_CONNECTION_STRING="${{ steps.infra.outputs.app-insights-connection }}" \
        YourCustomSetting="value"
```

---

## Summary

✅ **Azure Setup**: App registration with federated credential  
✅ **GitHub Secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`  
✅ **GitHub Variables**: `PROJECT_NAME`, `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`  
✅ **Workflows**: 
  - Infrastructure deployment with Terraform (triggers on `infra/**` changes)
  - MCP API deployment (triggers on `src/Customers.MCP/**` changes)

**Security Benefits**:
- No client secrets stored in GitHub
- Credentials are short-lived OIDC tokens
- Azure manages trust via federated credentials

**Deployment Flow**:
1. Infrastructure deploys with Terraform → Creates all Azure resources with state management
2. MCP API deploys → Builds .NET 10 app and deploys to Web App
3. Configuration is automatic (Cosmos DB endpoint, Application Insights)

## Infrastructure Technology

This project uses **Terraform** for infrastructure as code. The Terraform configuration files are located in the `infra/` directory:

- `main.tf` - Main resource definitions
- `providers.tf` - Provider configuration
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Example variable values

For local development and testing, see [infra/README.md](infra/README.md) for detailed Terraform usage instructions.

