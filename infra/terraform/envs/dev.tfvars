environment         = "dev"
location            = "eastus"
vnet_name           = "vnet-main"
resource_group_name = "rg-networking-dev"
vnet_address_space  = ["10.0.0.0/16"]

subnets = {
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

tags = {
  Project    = "networking"
  Owner      = "platform-team"
  CostCenter = "CC-1234"
}