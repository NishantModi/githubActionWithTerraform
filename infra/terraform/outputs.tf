# ──────────────────────────────────────────────────────────
# Outputs (visible in Terraform output & GitHub Actions logs)
# ──────────────────────────────────────────────────────────

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