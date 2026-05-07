# Basic public IP for RDP access (Static so it doesn't change on stop/start)
resource "azurerm_public_ip" "vm" {
  name                = "pip-${var.vm_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Basic"

  tags = var.tags
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-${var.vm_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }

  tags = var.tags
}

# Allow RDP inbound on the subnet's NSG
resource "azurerm_network_security_rule" "rdp" {
  name                        = "AllowRDP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = var.nsg_name
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.vm.id]

  os_disk {
    caching              = "ReadWrite"
    # Standard_LRS = Standard HDD — cheapest managed disk tier
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    # smalldisk variant: 30 GB OS disk instead of 128 GB — significantly reduces storage cost
    sku       = "2022-datacenter-smalldisk"
    version   = "latest"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}
