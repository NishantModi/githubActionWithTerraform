# ──────────────────────────────────────────────────────────
# Networking outputs
# ──────────────────────────────────────────────────────────

output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = module.networking.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet key to subnet ID"
  value       = module.networking.subnet_ids
}

output "nsg_ids" {
  description = "Map of subnet key to NSG ID"
  value       = module.networking.nsg_ids
}

# ──────────────────────────────────────────────────────────
# Windows VM outputs
# ──────────────────────────────────────────────────────────

output "windows_vm_id" {
  description = "Resource ID of the Windows VM"
  value       = module.windows_vm.vm_id
}

output "windows_vm_name" {
  description = "Name of the Windows VM"
  value       = module.windows_vm.vm_name
}

output "windows_vm_private_ip" {
  description = "Private IP address of the Windows VM"
  value       = module.windows_vm.private_ip_address
}

output "windows_vm_public_ip" {
  description = "Public IP for RDP — connect via mstsc /v:<ip>"
  value       = module.windows_vm.public_ip_address
}
