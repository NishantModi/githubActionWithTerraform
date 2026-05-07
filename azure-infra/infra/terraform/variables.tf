# ──────────────────────────────────────────────────────────
# Input Variables
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

variable "vnet_name" {
  description = "Name of the Virtual Network"
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
    address_prefixes = list(string)
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
  default     = "NishantModi-RG"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}