# Infrastructure as Code - Terraform

This directory contains Terraform configuration files for deploying the Azure infrastructure required for the Foundry IQ + Cosmos DB RAG Pattern Implementation.

## Files

- `main.tf` - Main Terraform configuration with all Azure resources
- `providers.tf` - Provider configuration for Azure Resource Manager
- `variables.tf` - Input variable definitions
- `outputs.tf` - Output value definitions
- `terraform.tfvars.example` - Example variable values (copy to `terraform.tfvars` and customize)
- `.gitignore` - Git ignore rules for Terraform files

## Resources Deployed

This Terraform configuration deploys the following Azure resources:

- **Azure Cosmos DB for NoSQL** - Document database with customers database and customer_spent container
- **Azure Storage Account** - Blob storage with customer-info container
- **Azure Web App** - Linux App Service hosting the MCP server API (.NET 10)
- **App Service Plan** - Basic tier (B1) Linux plan
- **Azure AI Search** - Standard tier search service with managed identity
- **User Assigned Managed Identities** - For Azure AI Search and Foundry services
- **Key Vault** - For secure secret storage with RBAC enabled
- **Cognitive Services Account** - AI Services (Foundry) with custom subdomain
- **Log Analytics Workspace** - Centralized logging
- **Application Insights** - Application performance monitoring
- **Role Assignments** - RBAC permissions for managed identities

## Prerequisites

1. **Terraform** >= 1.0 ([Download](https://www.terraform.io/downloads))
2. **Azure CLI** ([Download](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli))
3. **Azure Subscription** with appropriate permissions
4. **Resource Group** created in Azure

## Local Deployment

### 1. Login to Azure

```bash
az login
```

### 2. Set up variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_name        = "fiqftcosmos"
location            = "swedencentral"
resource_group_name = "rg-foundryiq-ft-cosmos"

common_tags = {
  Application = "Foundry-ft-Cosmos"
}
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan the deployment

```bash
terraform plan
```

Review the plan to ensure it will create the expected resources.

### 5. Apply the configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 6. View outputs

After deployment, view the outputs:

```bash
terraform output
```

To get a specific output value:

```bash
terraform output COSMOS_DB_ENDPOINT
terraform output WEB_APP_NAME
```

## GitHub Actions Deployment

The deployment is automated via GitHub Actions workflow (`.github/workflows/deploy-infra.yaml`).

### Required GitHub Secrets

Configure these secrets in your GitHub repository:

- `AZURE_CLIENT_ID` - Application (client) ID of the Entra ID App Registration
- `AZURE_TENANT_ID` - Azure Active Directory tenant ID
- `AZURE_SUBSCRIPTION_ID` - Target Azure subscription ID

### Required GitHub Variables

Configure these variables in your GitHub repository:

- `PROJECT_NAME` - Unique project identifier (e.g., `fiqftcosmos`)
- `AZURE_RESOURCE_GROUP` - Resource group name (e.g., `rg-foundryiq-ft-cosmos`)
- `AZURE_LOCATION` - Azure region (e.g., `swedencentral`)

### Workflow Triggers

The workflow runs automatically on:
- Push to `main` branch with changes in `infra/**`
- Manual trigger via workflow_dispatch

## State Management

For production deployments, it's recommended to configure a remote backend for Terraform state:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "terraformstate"
    container_name       = "tfstate"
    key                  = "foundry-ft-cosmos.tfstate"
  }
}
```

See the [Terraform Azure Backend documentation](https://www.terraform.io/docs/language/settings/backends/azurerm.html) for more details.

## Outputs

The following outputs are available after deployment:

- `AZURE_LOCATION` - Azure region where resources are deployed
- `AZURE_TENANT_ID` - Azure tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID
- `RESOURCE_GROUP_NAME` - Resource group name
- `APP_SERVICE_IDENTITY_PRINCIPAL_ID` - Web app managed identity principal ID
- `APPLICATION_INSIGHTS_CONNECTION_STRING` - Application Insights connection string (sensitive)
- `COSMOS_DB_ENDPOINT` - Cosmos DB endpoint URL
- `WEB_APP_NAME` - Web app name

## Post-Deployment Steps

After deploying the infrastructure, you'll need to:

1. **Grant Cosmos DB data plane permissions** to the Web App managed identity using the PowerShell script:
   ```powershell
   pwsh ./scripts/Set-CosmosDB-Dataplane-Owner.ps1 \
     <WEB_APP_PRINCIPAL_ID> \
     <RESOURCE_GROUP_NAME> \
     <COSMOS_DB_ACCOUNT_NAME>
   ```

2. **Configure Foundry connections** in the Azure AI Foundry management center

3. **Upload sample data** to the Storage Account and Cosmos DB

See the main [README.md](../README.md) for detailed post-deployment instructions.

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning:** This will delete all resources and data. Make sure you have backups if needed.

## Troubleshooting

### Resource naming conflicts

If you get naming conflicts, ensure your `project_name` is unique and follows Azure naming conventions:
- Lowercase letters and numbers only for storage accounts
- No special characters except hyphens for most resources
- Storage account names must be globally unique

### Permission errors

Ensure the account you're using has:
- Contributor role on the resource group
- Ability to create role assignments
- Ability to create managed identities

### Provider version issues

If you encounter provider compatibility issues, check the required provider version in `providers.tf` and update if necessary.

## Migration from Bicep

This Terraform configuration replaces the previous `main-simple.bicep` file. Key differences:

1. **State Management**: Terraform maintains state, while Bicep deployments are stateless
2. **Syntax**: HCL (Terraform) vs Bicep
3. **Workflow**: GitHub Actions workflow updated to use Terraform instead of ARM deployments
4. **Resource Properties**: Some property names differ between providers (e.g., `enable_rbac_authorization` → `rbac_authorization_enabled`)

All resources and configurations are functionally equivalent to the original Bicep deployment.
