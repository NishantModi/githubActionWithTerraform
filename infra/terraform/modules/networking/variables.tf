variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vnet_name" {
  description = "Base name for the Virtual Network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet in CIDR notation"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet configurations"
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
  }))
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
