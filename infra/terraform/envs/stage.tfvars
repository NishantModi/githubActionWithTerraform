environment         = "stage"
location            = "eastus"
vnet_name           = "vnet-stage"
resource_group_name = "NishantModi-RG"
vnet_address_space  = ["10.1.0.0/16"]

subnets = {
  web = {
    address_prefixes  = ["10.1.1.0/24"]
    service_endpoints = []
  }
  app = {
    address_prefixes  = ["10.1.2.0/24"]
    service_endpoints = ["Microsoft.Sql", "Microsoft.KeyVault"]
  }
  db = {
    address_prefixes  = ["10.1.3.0/24"]
    service_endpoints = ["Microsoft.Sql"]
  }
}

tags = {
  Project    = "networking"
  Owner      = "platform-team"
  CostCenter = "CC-1234"
}

# Windows VM
windows_vm_name           = "vm-win-stage"
windows_vm_size           = "Standard_B1ms"
windows_vm_admin_username = "azureadmin"
# windows_vm_admin_password — do NOT add here.
# Pass at plan/apply time:
#   export TF_VAR_windows_vm_admin_password="YourP@ssw0rd!"
#   terraform apply -var-file=envs/stage.tfvars
