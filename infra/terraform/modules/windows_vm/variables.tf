variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vm_name" {
  description = "Name of the Windows VM"
  type        = string
  default     = "vm-win"
}

# Standard_B1ms: 1 vCPU, 2 GB RAM — cheapest size that reliably runs Windows Server
variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B1ms"
}

variable "admin_username" {
  description = "Local administrator username"
  type        = string
}

variable "admin_password" {
  description = "Local administrator password — pass via TF_VAR_windows_vm_admin_password, never hardcode"
  type        = string
  sensitive   = true
}

variable "subnet_id" {
  description = "Subnet ID where the NIC will be attached"
  type        = string
}

variable "nsg_name" {
  description = "Name of the NSG to add the RDP inbound rule to"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
