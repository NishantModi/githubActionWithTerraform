output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  description = "Map of subnet key to subnet ID"
  value       = { for k, s in azurerm_subnet.subnets : k => s.id }
}

output "nsg_ids" {
  description = "Map of subnet key to NSG ID"
  value       = { for k, n in azurerm_network_security_group.subnets : k => n.id }
}

output "nsg_names" {
  description = "Map of subnet key to NSG name"
  value       = { for k, n in azurerm_network_security_group.subnets : k => n.name }
}
