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
2. Click **New repository variable** and add these **2 variables**:

| Variable Name | Value | Example |
|--------------|-------|---------|
| `AZURE_RESOURCE_GROUP` | Your resource group name | `rg-foundryiq-ft-cosmos` |
| `AZURE_LOCATION` | Azure region | `eastus` |

---

## Part 3: Verify Setup

### Test the Connection

You can manually trigger the workflow:
1. Go to **Actions** tab in GitHub
2. Select **Deploy Infrastructure**
3. Click **Run workflow** → **Run workflow**

Or push a change to the `infra/` folder on the `main` branch.

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

---

## Summary

✅ **Azure Setup**: App registration with federated credential  
✅ **GitHub Secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`  
✅ **GitHub Variables**: `AZURE_RESOURCE_GROUP`, `AZURE_LOCATION`  
✅ **Workflow**: Triggers on `main` branch changes to `infra/`  

**Security Benefits**:
- No client secrets stored in GitHub
- Credentials are short-lived tokens
- Azure manages trust via OIDC
