# End-to-End: Terraform Azure VNet via GitHub Actions with OIDC
### POC Completed on Windows (PowerShell) — All Commands Tested

---

## Architecture Overview

```
Developer Workstation (Windows)    GitHub                        Azure
┌─────────────────┐    ┌──────────────────┐    ┌──────────────────────────┐
│                 │    │                  │    │                          │
│ Terraform code  │───►│  GitHub Repo     │    │  Azure AD (Entra ID)     │
│ + workflow YAML │    │  .github/        │    │  ├── App Registration    │
│                 │    │   workflows/     │    │  └── Federated Credential│
│ git push        │    │                  │    │                          │
│                 │    │  GitHub Actions  │◄──►│  OIDC Token Exchange     │
│                 │    │  Runner          │    │                          │
│                 │    │  ├── tf init     │───►│  Resource Group          │
│                 │    │  ├── tf plan     │    │  └── Virtual Network     │
│                 │    │  └── tf apply    │    │      ├── subnet-web      │
│                 │    │                  │    │      ├── subnet-app      │
└─────────────────┘    └──────────────────┘    │      └── subnet-db       │
                                               └──────────────────────────┘
```

---

## STEP 1: Azure Prerequisites (PowerShell)

### 1.1 — Login and set subscription

```powershell
# Login to Azure
az login

# List subscriptions and pick the right one
az account list --output table

# Set your target subscription
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Verify
az account show --query "{name:name, id:id}" --output table
```

### 1.2 — Create a Resource Group for Terraform State

Terraform needs a backend to store its state file. We'll use Azure Blob Storage.

```powershell
# Create resource group for TF state (separate from infra RG)
az group create --name rg-tfstate --location eastus

# Create storage account (name must be globally unique, lowercase, no hyphens)
az storage account create `
  --name sttfstate<yourname> `
  --resource-group rg-tfstate `
  --location eastus `
  --sku Standard_LRS `
  --min-tls-version TLS1_2

# Create blob container
az storage container create `
  --name tfstate `
  --account-name sttfstate<yourname>
```

### 1.3 — Create Resource Group where VNet will live

```powershell
az group create --name rg-networking-dev --location eastus
```

---

## STEP 2: Azure AD (Entra ID) — App Registration + OIDC

This is the core of keyless authentication. No client secrets needed.

### 2.1 — Create the App Registration

```powershell
# Create app registration
az ad app create --display-name "github-actions-terraform"

# Store the App ID in a variable
# NOTE: In PowerShell use $VAR = command (NOT Bash syntax VAR=$(command))
$APP_ID = az ad app list --display-name "github-actions-terraform" --query "[0].appId" -o tsv
Write-Output "App ID: $APP_ID"
```

### 2.2 — Create a Service Principal for the App

> **IMPORTANT:** You must create the Service Principal BEFORE querying it.
> The App Registration and Service Principal are two separate objects in Azure AD.

```powershell
# Step 1: CREATE the service principal first
az ad sp create --id $APP_ID

# Step 2: THEN query its Object ID
$SP_OBJECT_ID = az ad sp show --id $APP_ID --query "id" -o tsv
Write-Output "SP Object ID: $SP_OBJECT_ID"
```

### 2.3 — Create the Federated Credential (OIDC Trust)

This tells Azure AD: "Trust tokens coming from GitHub Actions for THIS specific repo and branch."

> **CRITICAL:** The `subject` field must use `org/repo` format — NOT the full GitHub URL.
>
> - WRONG: `repo:https://github.com/NishantModi/githubActionWithTerraform:ref:refs/heads/main`
> - CORRECT: `repo:NishantModi/githubActionWithTerraform:ref:refs/heads/main`

> **PowerShell JSON Gotcha:** PowerShell strips double quotes from inline JSON strings,
> causing `az` to fail with "Failed to parse string as JSON". The fix is to save JSON
> to a file and pass the file path with `@` prefix.

```powershell
# Get the App's Object ID (different from SP Object ID)
$APP_OBJECT_ID = az ad app show --id $APP_ID --query "id" -o tsv

# Save JSON to a file (avoids PowerShell quote-stripping issues)
$json = '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:NishantModi/githubActionWithTerraform:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions OIDC for main branch"
}'

# Use Set-Content with ASCII encoding (Out-File adds BOM which corrupts JSON)
$json | Set-Content -Path .\cred.json -Encoding ASCII

# Pass the file path (note the @ prefix tells az to read from file)
az ad app federated-credential create --id $APP_OBJECT_ID --parameters "@cred.json"
```

**REQUIRED — Federated credential for the `dev` environment (needed for apply/destroy jobs):**

> **CRITICAL GOTCHA:** When a GitHub Actions job specifies `environment: dev`, the OIDC
> subject claim changes from `ref:refs/heads/main` to `environment:dev`. Without this
> credential, the plan job will succeed but the apply job will fail with:
> `AADSTS700213: No matching federated identity record found for presented assertion subject`
>
> The subject claim in the error will show `repo:NishantModi/githubActionWithTerraform:environment:dev`
> which won't match the `ref:refs/heads/main` credential. This is a security feature —
> environment-scoped tokens get separate trust policies.

```powershell
$jsonEnv = '{
  "name": "github-actions-env-dev",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:NishantModi/githubActionWithTerraform:environment:dev",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions OIDC for dev environment"
}'

$jsonEnv | Set-Content -Path .\cred-env-dev.json -Encoding ASCII
az ad app federated-credential create --id $APP_OBJECT_ID --parameters "@cred-env-dev.json"
```

**Optional — Federated credential for Pull Requests (plan-only access):**

```powershell
$jsonPR = '{
  "name": "github-actions-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:NishantModi/githubActionWithTerraform:pull_request",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions OIDC for pull requests"
}'

$jsonPR | Set-Content -Path .\cred-pr.json -Encoding ASCII
az ad app federated-credential create --id $APP_OBJECT_ID --parameters "@cred-pr.json"
```

> **Summary:** You need up to 3 federated credentials for a complete setup:
>
> | Credential | Subject Claim | Used By |
> |---|---|---|
> | `github-actions-main` | `repo:org/repo:ref:refs/heads/main` | Plan job (push to main) |
> | `github-actions-env-dev` | `repo:org/repo:environment:dev` | Apply + Destroy jobs |
> | `github-actions-pr` | `repo:org/repo:pull_request` | Plan job (on PRs) |

### 2.4 — Assign RBAC Roles to the Service Principal

```powershell
$SUBSCRIPTION_ID = az account show --query "id" -o tsv

# Role 1: Contributor on the networking resource group
az role assignment create `
  --assignee $APP_ID `
  --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-networking-dev"

# Role 2: Storage Blob Data Contributor on the TF state storage
az role assignment create `
  --assignee $APP_ID `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-tfstate"
```

### 2.5 — Collect the three values for GitHub Secrets

```powershell
$TENANT_ID = az account show --query "tenantId" -o tsv

Write-Output "=== Copy these to GitHub Secrets ==="
Write-Output "AZURE_CLIENT_ID:       $APP_ID"
Write-Output "AZURE_TENANT_ID:       $TENANT_ID"
Write-Output "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

No client secret. That's the whole point of OIDC — these three values are non-sensitive identifiers, not credentials.

---

## STEP 3: Create the GitHub Repository

### 3.1 — Create repo on GitHub

```powershell
# Option A: via GitHub CLI
gh repo create githubActionWithTerraform --private --clone
cd githubActionWithTerraform

# Option B: create on github.com, then clone
git clone https://github.com/NishantModi/githubActionWithTerraform.git
cd githubActionWithTerraform
```

### 3.2 — Create the folder structure

> **CRITICAL:** The `.github/workflows/` folder MUST be at the repo root.
> If it's nested inside a subfolder (e.g., `azure-infra/.github/workflows/`),
> GitHub Actions will NOT detect it and the workflow won't appear in the Actions tab.

```powershell
# Create folders at repo ROOT level
New-Item -ItemType Directory -Path ".github\workflows" -Force
New-Item -ItemType Directory -Path "infra\terraform\envs" -Force
```

Your repo must look exactly like this:

```
githubActionWithTerraform/          ← repo root
├── .github/
│   └── workflows/
│       └── terraform.yml           ← GitHub detects this
├── infra/
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       └── envs/
│           └── dev.tfvars
├── .gitignore
└── README.md
```

> **Lesson Learned:** If you accidentally created files inside a subfolder like `azure-infra/`,
> move them to the repo root:
> ```powershell
> Move-Item -Path .\azure-infra\* -Destination .\ -Force
> Move-Item -Path .\azure-infra\.github -Destination .\ -Force
> Move-Item -Path .\azure-infra\.gitignore -Destination .\ -Force
> Remove-Item -Path .\azure-infra -Recurse
> ```

---

## STEP 4: Write the Terraform Code

### 4.1 — `infra/terraform/providers.tf`

```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Remote backend — state stored in Azure Blob Storage
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate<yourname>"     # ← Replace with yours
    container_name       = "tfstate"
    key                  = "networking-dev.tfstate"
    use_oidc             = true                       # ← Critical for OIDC!
  }
}

provider "azurerm" {
  features {}
  use_oidc = true    # Tells provider to use OIDC (no client_secret needed)
}
```

**Key callout:** The `use_oidc = true` in BOTH the backend AND provider block is what makes keyless auth work.

### 4.2 — `infra/terraform/variables.tf`

```hcl
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = "vnet-main"
}

variable "vnet_address_space" {
  description = "Address space for the VNet in CIDR notation"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnets" {
  description = "Map of subnet configurations"
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
  }))
  default = {
    web = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = []
    }
    app = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Sql", "Microsoft.KeyVault"]
    }
    db = {
      address_prefixes  = ["10.0.3.0/24"]
      service_endpoints = ["Microsoft.Sql"]
    }
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-networking-dev"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
```

### 4.3 — `infra/terraform/main.tf`

```hcl
# Reference existing resource group (created in Step 1.3)
data "azurerm_resource_group" "networking" {
  name = var.resource_group_name
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.vnet_name}-${var.environment}"
  location            = data.azurerm_resource_group.networking.location
  resource_group_name = data.azurerm_resource_group.networking.name
  address_space       = var.vnet_address_space

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "githubActionWithTerraform"
  })
}

# Subnets (created dynamically from the variable map)
resource "azurerm_subnet" "subnets" {
  for_each = var.subnets

  name                 = "snet-${each.key}-${var.environment}"
  resource_group_name  = data.azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints
}

# Network Security Groups (one per subnet — best practice)
resource "azurerm_network_security_group" "subnets" {
  for_each = var.subnets

  name                = "nsg-${each.key}-${var.environment}"
  location            = data.azurerm_resource_group.networking.location
  resource_group_name = data.azurerm_resource_group.networking.name

  tags = merge(var.tags, {
    Environment = var.environment
    Subnet      = each.key
  })
}

# Associate NSGs with their respective subnets
resource "azurerm_subnet_network_security_group_association" "subnets" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.subnets[each.key].id
}
```

### 4.4 — `infra/terraform/outputs.tf`

```hcl
output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value = {
    for key, subnet in azurerm_subnet.subnets :
    key => subnet.id
  }
}

output "nsg_ids" {
  description = "Map of NSG name to NSG ID"
  value = {
    for key, nsg in azurerm_network_security_group.subnets :
    key => nsg.id
  }
}
```

### 4.5 — `infra/terraform/envs/dev.tfvars`

```hcl
environment         = "dev"
location            = "eastus"
vnet_name           = "vnet-main"
resource_group_name = "rg-networking-dev"
vnet_address_space  = ["10.0.0.0/16"]

subnets = {
  web = {
    address_prefixes  = ["10.0.1.0/24"]
    service_endpoints = []
  }
  app = {
    address_prefixes  = ["10.0.2.0/24"]
    service_endpoints = ["Microsoft.Sql", "Microsoft.KeyVault"]
  }
  db = {
    address_prefixes  = ["10.0.3.0/24"]
    service_endpoints = ["Microsoft.Sql"]
  }
}

tags = {
  Project    = "networking"
  Owner      = "platform-team"
  CostCenter = "CC-1234"
}
```

### 4.6 — `.gitignore` (at repo root)

```gitignore
# Terraform
*.tfstate
*.tfstate.*
*.tfplan
.terraform/
.terraform.lock.hcl
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
*.auto.tfvars

# Credential files used during setup
cred.json
cred-pr.json
cred-env-dev.json

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
```

---

## STEP 5: Create the GitHub Actions Workflow

### `.github/workflows/terraform.yml`

```yaml
name: "Terraform Azure Networking"

on:
  pull_request:
    branches: [main]
    paths:
      - 'infra/terraform/**'
  push:
    branches: [main]
    paths:
      - 'infra/terraform/**'
  workflow_dispatch:
    inputs:
      action:
        description: 'Terraform action to perform'
        required: true
        type: choice
        options:
          - plan
          - apply
          - destroy

permissions:
  id-token: write
  contents: read
  pull-requests: write

concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  TF_VERSION: "1.7.5"
  WORKING_DIR: "infra/terraform"
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_USE_OIDC: true
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true   # Avoids Node.js 20 deprecation warnings

jobs:

  # ════════════════════════════════════════════════════════
  # JOB 1: Terraform Plan
  # ════════════════════════════════════════════════════════
  terraform-plan:
    name: "Terraform Plan"
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}
    outputs:
      has-changes: ${{ steps.plan.outputs.exitcode == '2' }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
          terraform_wrapper: true

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        id: init
        run: terraform init

      - name: Terraform Format Check
        id: fmt
        run: terraform fmt -check -recursive
        continue-on-error: true

      - name: Terraform Validate
        id: validate
        run: terraform validate -no-color

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan \
            -var-file="envs/dev.tfvars" \
            -out=tfplan \
            -detailed-exitcode \
            -no-color
        continue-on-error: true

      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        env:
          PLAN: ${{ steps.plan.outputs.stdout }}
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const output = `### Terraform Plan Results

            #### Format: \`${{ steps.fmt.outcome }}\`
            #### Validate: \`${{ steps.validate.outcome }}\`
            #### Plan: \`${{ steps.plan.outcome }}\`

            <details><summary>Show Plan Output</summary>

            \`\`\`terraform
            ${process.env.PLAN}
            \`\`\`

            </details>

            *Pushed by: @${{ github.actor }}, Action: \`${{ github.event_name }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output.substring(0, 65536)
            });

      - name: Check Plan Status
        if: steps.plan.outputs.exitcode == '1'
        run: exit 1

      - name: Upload Plan
        if: steps.plan.outputs.exitcode == '2'
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: ${{ env.WORKING_DIR }}/tfplan
          retention-days: 5

  # ════════════════════════════════════════════════════════
  # JOB 2: Terraform Apply
  # ════════════════════════════════════════════════════════
  terraform-apply:
    name: "Terraform Apply"
    needs: terraform-plan
    if: |
      (github.ref == 'refs/heads/main' && github.event_name == 'push') ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply')
    runs-on: ubuntu-latest
    environment:
      name: dev
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        run: terraform init

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: ${{ env.WORKING_DIR }}

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan

      - name: Show Outputs
        run: terraform output -json

  # ════════════════════════════════════════════════════════
  # JOB 3: Terraform Destroy (manual only)
  # ════════════════════════════════════════════════════════
  terraform-destroy:
    name: "Terraform Destroy"
    if: |
      github.event_name == 'workflow_dispatch' &&
      github.event.inputs.action == 'destroy'
    runs-on: ubuntu-latest
    environment:
      name: dev
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        run: terraform init

      - name: Terraform Destroy
        run: |
          terraform destroy \
            -var-file="envs/dev.tfvars" \
            -auto-approve
```

---

## STEP 6: Configure GitHub Repository Settings

### 6.1 — Add Secrets

Go to: **GitHub Repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | Output from Step 2.5 |
| `AZURE_TENANT_ID` | Output from Step 2.5 |
| `AZURE_SUBSCRIPTION_ID` | Output from Step 2.5 |

**Or via CLI:**
```powershell
gh secret set AZURE_CLIENT_ID --body "<your-client-id>"
gh secret set AZURE_TENANT_ID --body "<your-tenant-id>"
gh secret set AZURE_SUBSCRIPTION_ID --body "<your-subscription-id>"
```

### 6.2 — Create Environment

Go to: **GitHub Repo → Settings → Environments → New environment**

- Name: `dev`
- (Optional) Add required reviewers for approval gates
- (Optional) Limit deployment branches to `main`

---

## STEP 7: Push Code and Trigger the Pipeline

### 7.1 — Fix Git credentials (if needed)

> **Windows Issue:** If Git is authenticating as the wrong user (e.g., a colleague's account),
> remove the cached credential:
>
> ```powershell
> # Open Windows Credential Manager
> control /name Microsoft.CredentialManager
> ```
>
> Go to **Windows Credentials** → find `git:https://github.com` → **Remove**.
>
> **Alternative** — force your identity for this repo:
> ```powershell
> git remote set-url origin https://NishantModi@github.com/NishantModi/githubActionWithTerraform.git
> ```

### 7.2 — Initial push to main (one-time bootstrap)

> **IMPORTANT:** The `workflow_dispatch` trigger (manual "Run workflow" button) only
> appears in the GitHub Actions tab AFTER the workflow YAML file exists on the `main`
> branch. For the very first push, go directly to main:

```powershell
git add -A
git commit -m "feat: add terraform vnet config + github actions pipeline"

# If remote main has a README you don't have locally:
git pull origin main --rebase

git push origin main
```

> **If push is rejected with "non-fast-forward":** For a brand-new repo with no
> collaborators, force push is safe:
> ```powershell
> git push origin main --force
> ```

### 7.3 — Verify the workflow appears

1. Go to `github.com/NishantModi/githubActionWithTerraform`
2. Click the **Actions** tab
3. You should see **"Terraform Azure Networking"** in the left sidebar
4. Click it → **Run workflow** → select **plan** → click **Run workflow**

### 7.4 — Future changes: use the PR workflow

After the initial bootstrap, always use feature branches:

```powershell
# Create feature branch
git checkout -b feature/update-vnet-config

# Make changes, commit
git add -A
git commit -m "feat: add new subnet for AKS"
git push -u origin feature/update-vnet-config

# Create PR via CLI
gh pr create --title "Add AKS subnet" --body "Adds snet-aks with service endpoints"
```

This triggers the plan job → posts plan as PR comment → reviewer approves → merge → apply runs automatically.

### 7.5 — Verify resources in Azure

```powershell
# Check VNet
az network vnet show `
  --name vnet-main-dev `
  --resource-group rg-networking-dev `
  --query "{name:name, addressSpace:addressSpace.addressPrefixes, subnets:subnets[].name}" `
  --output table

# Check subnets
az network vnet subnet list `
  --vnet-name vnet-main-dev `
  --resource-group rg-networking-dev `
  --output table
```

---

## STEP 8: Manual Trigger (workflow_dispatch)

For on-demand runs without pushing code:

**Via GitHub UI:**
Actions → Terraform Azure Networking → Run workflow → select plan/apply/destroy

**Via CLI:**
```powershell
# Plan only
gh workflow run "Terraform Azure Networking" --field action=plan

# Apply
gh workflow run "Terraform Azure Networking" --field action=apply

# Destroy (cleanup)
gh workflow run "Terraform Azure Networking" --field action=destroy
```

---

## Quick Reference: What Each File Does

| File | Purpose |
|---|---|
| `providers.tf` | Configures Azure provider + backend, enables OIDC |
| `variables.tf` | Defines all input parameters with types and defaults |
| `main.tf` | Creates VNet, subnets (dynamic), NSGs, and associations |
| `outputs.tf` | Exports resource IDs for use by other Terraform modules |
| `envs/dev.tfvars` | Dev-specific values (CIDR ranges, tags, names) |
| `terraform.yml` | GitHub Actions workflow: plan on PR, apply on merge |

---

## The Three YAML Sections That Make OIDC Work

All three must be present or authentication fails:

```
┌─ terraform.yml ───────────────────────────────────┐
│                                                    │
│  permissions:                                      │
│    id-token: write    ← Runner can request JWT     │
│                                                    │
│  env:                                              │
│    ARM_USE_OIDC: true ← azurerm provider uses OIDC │
│                                                    │
└────────────────────────────────────────────────────┘

┌─ providers.tf ────────────────────────────────────┐
│                                                    │
│  backend "azurerm" {                               │
│    use_oidc = true    ← Backend auth uses OIDC     │
│  }                                                 │
│                                                    │
│  provider "azurerm" {                              │
│    use_oidc = true    ← Provider auth uses OIDC    │
│  }                                                 │
│                                                    │
└────────────────────────────────────────────────────┘
```

Remove any one of these and you get "client secret required" errors.

---

## Troubleshooting — Issues Hit During This POC

| Issue | Symptom | Fix |
|---|---|---|
| Bash syntax in PowerShell | `APP_ID=$(...)` not recognized | Use `$APP_ID = az ...` (PowerShell assignment) |
| SP not created before query | "Resource does not exist" | Run `az ad sp create --id $APP_ID` first |
| Full URL in subject claim | `repo:https://github.com/...` | Use `repo:NishantModi/githubActionWithTerraform:ref:refs/heads/main` |
| PowerShell strips JSON quotes | "Failed to parse string as JSON" | Save to file + `Set-Content -Encoding ASCII` + pass `@cred.json` |
| `Out-File` adds BOM | "Expecting value: line 1 column 1" | Use `Set-Content -Encoding ASCII` instead of `Out-File -Encoding utf8` |
| Wrong Git credentials | "Permission denied to tahir-ansari-nv" | Remove cached credential in Windows Credential Manager |
| git push rejected | "remote contains work you don't have" | `git pull origin main --rebase` then push |
| git push non-fast-forward | Branch tip behind remote | `git push origin main --force` (safe for new repos) |
| Workflow not visible in Actions | "Get started with GitHub Actions" page | `.github/workflows/` must be at repo root, not in subfolder |
| Files in subfolder | `azure-infra/.github/workflows/` | Move all files to repo root with `Move-Item` |
| No "Run workflow" button | Manual trigger not showing | `workflow_dispatch` must exist in the YAML on the `main` branch |
| Node.js 20 deprecation | "Node.js 20 actions are deprecated" | Add `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` to workflow env |
| TF state container not found | `ContainerNotFound` on `terraform init` | Create storage account + blob container, match name in `providers.tf` |
| Missing tfvars file | "Given variables file envs/dev.tfvars does not exist" | Create `infra/terraform/envs/dev.tfvars` and commit to repo |
| OIDC works for plan, fails for apply | `AADSTS700213: No matching federated identity record` | Jobs with `environment:` change the OIDC subject claim — create a separate federated credential with `subject: repo:org/repo:environment:dev` |
| OIDC auth fails | "No matching federated credential" | Check `subject` claim matches repo/branch/environment exactly |
| Terraform init fails | "client secret required" | Ensure `use_oidc = true` in both backend AND provider |

---

## Cleanup — Delete Everything After POC

```powershell
# 1. Destroy Azure resources via workflow
gh workflow run "Terraform Azure Networking" --field action=destroy

# 2. Delete RBAC assignments
az role assignment delete --assignee $APP_ID --role "Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-networking-dev"

az role assignment delete --assignee $APP_ID --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-tfstate"

# 3. Delete App Registration (also removes SP and federated credentials)
az ad app delete --id $APP_ID

# 4. Delete resource groups
az group delete --name rg-networking-dev --yes --no-wait
az group delete --name rg-tfstate --yes --no-wait

# 5. Delete GitHub repo (optional)
gh repo delete NishantModi/githubActionWithTerraform --yes
```
