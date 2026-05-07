# ──────────────────────────────────────────────────────────
# Provider & Backend Configuration
# ──────────────────────────────────────────────────────────

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
    resource_group_name  = "NishantModi-RG"         # ← Replace with yours
    storage_account_name = "stotfstate07052026"     # ← Replace with yours
    container_name       = "tfstate"
    key                  = "networking-dev.tfstate"
    use_oidc             = true                       # ← Critical for OIDC!
  }
}

provider "azurerm" {
  features {}

  # These tell the provider to use OIDC (no client_secret needed)
  use_oidc = true

  # These are read from environment variables set by the GitHub Actions
  # workflow: ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
  # You do NOT hardcode them here.
}