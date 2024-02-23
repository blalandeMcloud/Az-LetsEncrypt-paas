#######################################
### Resource group
#######################################
resource "azurerm_resource_group" "rg-prod-network" {
  provider = azurerm.prod
  name     = "rg-prod-network-001"
  location = var.location
  tags = merge(
    var.tags
  )
}

resource "azurerm_resource_group" "rg-prod-appgw" {
  provider = azurerm.prod
  name     = "rg-prod-appgw-001"
  location = var.location

  tags = merge(
    var.tags
  )
}


#######################################
### vnet
#######################################

resource "azurerm_virtual_network" "vnet-prod" {
  provider = azurerm.prod

  name                = "vnet-prod-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-prod-network.name
  address_space       = ["10.24.0.0/16"]

  tags = merge(
    var.tags
  )

}

resource "azurerm_subnet" "snet-prod-appgw" {
  provider             = azurerm.prod
  name                 = "snet-10_24_0_0-24-appgw"
  resource_group_name  = azurerm_resource_group.rg-prod-network.name
  virtual_network_name = azurerm_virtual_network.vnet-prod.name
  address_prefixes     = ["10.24.0.0/24"]
}

### PEERING ###
resource "azurerm_virtual_network_peering" "prod-to-hub" {
  provider                  = azurerm.prod
  name                      = "peer_prod_to_hub"
  resource_group_name       = azurerm_resource_group.rg-prod-network.name
  virtual_network_name      = azurerm_virtual_network.vnet-prod.name
  remote_virtual_network_id = azurerm_virtual_network.vnet-hub.id
}

#######################################
### Application gateway
#######################################

locals {
  backend_address_pool_name      = "bck-test"
  frontend_port_name_80          = "feport-80"
  frontend_port_name_443         = "feport-443"
  frontend_ip_configuration_name = "feip-public"
  http_setting_name              = "hset-test-80"
  listener_name                  = "list-test-public-80"
  request_routing_rule_name      = "rule-test-public"
  redirect_configuration_name    = "redirect-storage-Account"
}

resource "azurerm_user_assigned_identity" "agw-mi" {
  provider            = azurerm.prod
  location            = azurerm_resource_group.rg-prod-appgw.location
  name                = "mid-agw-fc-prod-001"
  resource_group_name = azurerm_resource_group.rg-prod-appgw.name

  tags = merge(
    var.tags
  )
}

resource "azurerm_role_assignment" "role-agw-to-kv-admin" {
  provider             = azurerm.prod
  scope                = azurerm_key_vault.kv-hub.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.agw-mi.principal_id
}


resource "azurerm_public_ip" "pip-appgw" {
  provider            = azurerm.prod
  name                = "pip-appgw-001"
  resource_group_name = azurerm_resource_group.rg-prod-appgw.name
  location            = azurerm_resource_group.rg-prod-appgw.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label = "pip-appgw-001"

  tags = merge(
    var.tags
  )
}

resource "azurerm_application_gateway" "appgw-prod" {
  provider            = azurerm.prod
  name                = "agw-fc-prod-001"
  resource_group_name = azurerm_resource_group.rg-prod-appgw.name
  location            = azurerm_resource_group.rg-prod-appgw.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.snet-prod-appgw.id
  }

  frontend_port {
    name = local.frontend_port_name_80
    port = 80
  }

  frontend_port {
    name = local.frontend_port_name_443
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.pip-appgw.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name_80
    protocol                       = "Http"
    host_name                      = "test.bla-formation.com"
  }


  redirect_configuration {
    name                 = "redirect-letsencrypt"
    redirect_type        = "Permanent"
    target_url           = "https://${azurerm_storage_account.sa-letsencrypt.name}.blob.core.windows.net/public"
    include_path         = true
    include_query_string = true
  }

  # URL Path Map - Define Path based Routing    
  url_path_map {
    name                               = "url_path_letsencrypt"
    default_backend_address_pool_name  = local.backend_address_pool_name
    default_backend_http_settings_name = local.http_setting_name

    path_rule {
      name                        = "letsencrypt"
      paths                       = ["/.well-known/acme-challenge/*"]
      redirect_configuration_name = "redirect-letsencrypt"
    }

  }

  request_routing_rule {
    name               = local.request_routing_rule_name
    priority           = 1
    rule_type          = "PathBasedRouting"
    http_listener_name = local.listener_name
    url_path_map_name  = "url_path_letsencrypt"
  }

  tags = merge(
    var.tags
  )
}