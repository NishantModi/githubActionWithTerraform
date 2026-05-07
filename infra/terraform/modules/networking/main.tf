data "azurerm_resource_group" "networking" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.vnet_name}-${var.environment}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.networking.name
  address_space       = var.vnet_address_space

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "azure-infra"
  })
}

resource "azurerm_subnet" "subnets" {
  for_each = var.subnets

  name                 = "snet-${each.key}-${var.environment}"
  resource_group_name  = data.azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints
}

resource "azurerm_network_security_group" "subnets" {
  for_each = var.subnets

  name                = "nsg-${each.key}-${var.environment}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.networking.name

  tags = merge(var.tags, {
    Environment = var.environment
    Subnet      = each.key
  })
}

resource "azurerm_subnet_network_security_group_association" "subnets" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.subnets[each.key].id
}
