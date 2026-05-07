output "vm_id" {
  description = "Resource ID of the Windows VM"
  value       = azurerm_windows_virtual_machine.vm.id
}

output "vm_name" {
  description = "Name of the Windows VM"
  value       = azurerm_windows_virtual_machine.vm.name
}

output "private_ip_address" {
  description = "Private IP address of the VM NIC"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "public_ip_address" {
  description = "Public IP address for RDP access"
  value       = azurerm_public_ip.vm.ip_address
}
