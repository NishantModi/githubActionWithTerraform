# ──────────────────────────────────────────────────────────
# Shared
# ──────────────────────────────────────────────────────────

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
  default     = "NishantModi-RG"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ──────────────────────────────────────────────────────────
# Networking
# ──────────────────────────────────────────────────────────

variable "vnet_name" {
  description = "Base name of the Virtual Network"
  type        = string
  default     = "vnet-centralindia"
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

# ──────────────────────────────────────────────────────────
# Windows VM
# ──────────────────────────────────────────────────────────

variable "windows_vm_name" {
  description = "Name of the Windows VM"
  type        = string
  default     = "vm-win"
}

variable "windows_vm_size" {
  description = "Azure VM size — Standard_B1ms is the cheapest size that reliably runs Windows Server"
  type        = string
  default     = "Standard_B1ms"
}

variable "windows_vm_admin_username" {
  description = "Local administrator username for the Windows VM"
  type        = string
  default     = "azureadmin"
}

variable "windows_vm_admin_password" {
  description = "Local administrator password — supply via TF_VAR_windows_vm_admin_password env var, never hardcode"
  type        = string
  sensitive   = true
}
