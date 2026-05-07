module "networking" {
  source = "./modules/networking"

  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = var.environment
  vnet_name           = var.vnet_name
  vnet_address_space  = var.vnet_address_space
  subnets             = var.subnets
  tags                = var.tags
}

module "windows_vm" {
  source = "./modules/windows_vm"

  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = var.environment
  vm_name             = var.windows_vm_name
  vm_size             = var.windows_vm_size
  admin_username      = var.windows_vm_admin_username
  admin_password      = var.windows_vm_admin_password

  # Place the VM in the "web" subnet; its NSG gets the RDP rule
  subnet_id = module.networking.subnet_ids["web"]
  nsg_name  = module.networking.nsg_names["web"]

  tags = var.tags
}
