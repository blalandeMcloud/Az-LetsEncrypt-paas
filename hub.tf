data "azurerm_client_config" "current" {}

locals {
  prefix              = "demo"
  SubName             = "sub-lyon-03"
  KeyVaultName        = "kv-hub-certificat-001"
  STResourceGroupName = "rg-hub-letsencrypt${local.prefix}"
  storageName         = "saletsencrypt${local.prefix}"
  EmailAddress        = "test@test.com"
  monip               = "85.169.110.162/30"
}

#######################################
### Resource group
#######################################
resource "azurerm_resource_group" "rg-hub-network" {
  name     = "rg-hub-network-001"
  location = var.location
  tags = merge(
    var.tags
  )
}
resource "azurerm_resource_group" "rg-hub-letsencrypt" {
  name     = local.STResourceGroupName
  location = var.location
  tags = merge(
    var.tags
  )
}

#######################################
### vnet
#######################################

resource "azurerm_virtual_network" "vnet-hub" {
  name                = "vnet-hub-001"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-hub-network.name
  address_space       = ["10.23.0.0/16"]

  tags = merge(
    var.tags
  )
}

resource "azurerm_subnet" "snet-hub-secu" {
  name                 = "snet-10_23_0_0-27-secu"
  resource_group_name  = azurerm_resource_group.rg-hub-network.name
  virtual_network_name = azurerm_virtual_network.vnet-hub.name
  address_prefixes     = ["10.23.0.0/27"]
}

resource "azurerm_subnet" "snet-hub-appfunvnetint" {
  name                 = "snet-10_23_1_0-27-appfunvnetint"
  resource_group_name  = azurerm_resource_group.rg-hub-network.name
  virtual_network_name = azurerm_virtual_network.vnet-hub.name
  address_prefixes     = ["10.23.1.0/27"]

  delegation {

    name = "delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_role_assignment" "role-func-to-vnet" {
  scope                = azurerm_virtual_network.vnet-prod.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.funcletsencrypt.identity.0.principal_id
}

### PEERING ###
resource "azurerm_virtual_network_peering" "hub-to-prod" {
  name                      = "peer_hub_to_prod"
  resource_group_name       = azurerm_resource_group.rg-hub-network.name
  virtual_network_name      = azurerm_virtual_network.vnet-hub.name
  remote_virtual_network_id = azurerm_virtual_network.vnet-prod.id
}

#######################################
### Private dns Zone
#######################################

### Private dns zone for PE blob
resource "azurerm_private_dns_zone" "dns-blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name

  tags = merge(
    var.tags
  )
}

resource "azurerm_private_dns_zone_virtual_network_link" "link-sa-vnethub-blob" {
  name                  = "link-vnethub"
  resource_group_name   = azurerm_resource_group.rg-hub-letsencrypt.name
  private_dns_zone_name = azurerm_private_dns_zone.dns-blob.name
  virtual_network_id    = azurerm_virtual_network.vnet-hub.id

  tags = merge(
    var.tags
  )
}

### Private dns zone for PE file
resource "azurerm_private_dns_zone" "dns-file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name

  tags = merge(
    var.tags
  )
}

resource "azurerm_private_dns_zone_virtual_network_link" "link-sa-vnethub-file" {
  name                  = "link-vnethub"
  resource_group_name   = azurerm_resource_group.rg-hub-letsencrypt.name
  private_dns_zone_name = azurerm_private_dns_zone.dns-file.name
  virtual_network_id    = azurerm_virtual_network.vnet-hub.id

  tags = merge(
    var.tags
  )
}

### Private dns zone for website file
resource "azurerm_private_dns_zone" "dns-web" {
  name                = "privatelink.azurewebsite.net"
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name

  tags = merge(
    var.tags
  )
}

resource "azurerm_private_dns_zone_virtual_network_link" "link-sa-vnethub-web" {
  name                  = "link-vnethub"
  resource_group_name   = azurerm_resource_group.rg-hub-letsencrypt.name
  private_dns_zone_name = azurerm_private_dns_zone.dns-web.name
  virtual_network_id    = azurerm_virtual_network.vnet-hub.id

  tags = merge(
    var.tags
  )
}

### Private dns zone Keyvault
resource "azurerm_private_dns_zone" "dns-kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name

  tags = merge(
    var.tags
  )
}

resource "azurerm_private_dns_zone_virtual_network_link" "link-kv-vnethub" {
  name                  = "link-vnethub"
  resource_group_name   = azurerm_resource_group.rg-hub-letsencrypt.name
  private_dns_zone_name = azurerm_private_dns_zone.dns-kv.name
  virtual_network_id    = azurerm_virtual_network.vnet-hub.id

  tags = merge(
    var.tags
  )
}

resource "azurerm_private_dns_zone_virtual_network_link" "link-kv-vnetprod" {
  name                  = "link-vnetprod"
  resource_group_name   = azurerm_resource_group.rg-hub-letsencrypt.name
  private_dns_zone_name = azurerm_private_dns_zone.dns-kv.name
  virtual_network_id    = azurerm_virtual_network.vnet-prod.id

  tags = merge(
    var.tags
  )
}


#######################################
### Keyvault
#######################################

resource "azurerm_key_vault" "kv-hub" {

  name                          = local.KeyVaultName
  location                      = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name           = azurerm_resource_group.rg-hub-letsencrypt.name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  sku_name                      = "standard"
  public_network_access_enabled = false


  tags = merge(
    var.tags
  )
}

resource "azurerm_private_endpoint" "pe-kv-hub" {
  name                = "pe-${azurerm_key_vault.kv-hub.name}"
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  subnet_id           = azurerm_subnet.snet-hub-secu.id
  private_service_connection {
    name                           = "psc-pe-kv-hub"
    private_connection_resource_id = azurerm_key_vault.kv-hub.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns-kv.id]
  }

  tags = merge(
    var.tags
  )
}

resource "azurerm_role_assignment" "role-func-to-kv-contributor" {
  scope                = azurerm_key_vault.kv-hub.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.funcletsencrypt.identity.0.principal_id
}

resource "azurerm_role_assignment" "role-func-to-kv-admin" {
  scope                = azurerm_key_vault.kv-hub.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_linux_function_app.funcletsencrypt.identity.0.principal_id
}


#######################################
### Storage account for token
#######################################

resource "azurerm_storage_account" "sa-letsencrypt" {
  name                     = local.storageName
  resource_group_name      = azurerm_resource_group.rg-hub-letsencrypt.name
  location                 = azurerm_resource_group.rg-hub-letsencrypt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"
  is_hns_enabled           = true


  tags = merge(
    var.tags
  )
}

resource "azurerm_storage_container" "sa-container-public" {
  name                  = "public"
  storage_account_name  = azurerm_storage_account.sa-letsencrypt.name
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "blob-index-test" {
  name                   = ".well-known/acme-challenge/index.html"
  storage_account_name   = azurerm_storage_account.sa-letsencrypt.name
  storage_container_name = azurerm_storage_container.sa-container-public.name
  type                   = "Block"
  content_type           = "text/html"
  source                 = "file/index.html"
}

resource "azurerm_role_assignment" "role-func-to-saletsencrypt" {
  scope                = azurerm_storage_account.sa-letsencrypt.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.funcletsencrypt.identity.0.principal_id
}

resource "azurerm_role_assignment" "role-func-to-saletsencrypt-blob" {
  scope                = azurerm_storage_account.sa-letsencrypt.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.funcletsencrypt.identity.0.principal_id
}


#######################################
### Azure Function
#######################################

#### app function storage account
resource "azurerm_storage_account" "safuncletsencryptdemo" {
  name                     = "safuncletsencrypt${local.prefix}001"
  resource_group_name      = azurerm_resource_group.rg-hub-letsencrypt.name
  location                 = azurerm_resource_group.rg-hub-letsencrypt.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
    
  #Terraform doit accéder a ce compte de stockage pour importer les functions (zip)
  #Commenter cette ligne pour tester depuis internet
  #Decommenter cette ligne, Si vous lancez le terraform depuis un réseau interne et bloquer l'accès depuis internet 
  #public_network_access_enabled = false


  tags = merge(
    var.tags
  )
}

resource "azurerm_private_endpoint" "pe-safuncletsencryptdemo-blob" {
  name                = "pe-${azurerm_storage_account.sa-letsencrypt.name}-blob"
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  subnet_id           = azurerm_subnet.snet-hub-secu.id
  private_service_connection {
    name                           = "psc-pe-${azurerm_storage_account.sa-letsencrypt.name}-blob"
    private_connection_resource_id = azurerm_storage_account.safuncletsencryptdemo.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns-blob.id]
  }

  tags = merge(
    var.tags
  )
}

resource "azurerm_private_endpoint" "pe-safuncletsencryptdemo-file" {
  name                = "pe-${azurerm_storage_account.sa-letsencrypt.name}-file"
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  subnet_id           = azurerm_subnet.snet-hub-secu.id
  private_service_connection {
    name                           = "psc-pe-${azurerm_storage_account.sa-letsencrypt.name}-file"
    private_connection_resource_id = azurerm_storage_account.safuncletsencryptdemo.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns-file.id]
  }

  tags = merge(
    var.tags
  )
}


#### APP Service

data "archive_file" "powershell_function_package" {
  type        = "zip"
  source_dir  = "file/function"
  output_path = "function.zip"
}

resource "azurerm_service_plan" "appplanfunc" {
  name                = "appplan-funcletsencrypt"
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  os_type             = "Linux"
  sku_name            = "P0v3"

  tags = merge(
    var.tags
  )
}

resource "azurerm_linux_function_app" "funcletsencrypt" {
  name                = "funcletsencrypt${local.prefix}001"
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  location            = azurerm_resource_group.rg-hub-letsencrypt.location

  storage_account_name       = azurerm_storage_account.safuncletsencryptdemo.name
  storage_account_access_key = azurerm_storage_account.safuncletsencryptdemo.primary_access_key
  service_plan_id            = azurerm_service_plan.appplanfunc.id

  #Commenter cette ligne pour tester depuis internet
  #decommenter cette ligne pour bloquer l'accès depuis internet et tester depuis un réseau interne
  #public_network_access_enabled = false

  virtual_network_subnet_id = azurerm_subnet.snet-hub-appfunvnetint.id

  site_config {

    application_stack {
      powershell_core_version = "7.2"
    }

    always_on = true

    cors {
      allowed_origins = ["https://portal.azure.com"]
    }

    application_insights_connection_string = azurerm_application_insights.ins-func.connection_string
    application_insights_key = azurerm_application_insights.ins-func.instrumentation_key
  }

  zip_deploy_file = data.archive_file.powershell_function_package.output_path

  app_settings = {
    # app specific variables
    "SubName"                  = local.SubName
    "EmailAddress"             = local.KeyVaultName
    "EmailAddress"             = local.EmailAddress
    "STResourceGroupName"      = local.STResourceGroupName
    "storageName"              = local.storageName
    "WEBSITE_RUN_FROM_PACKAGE" = 1
    "WEBSITE_CONTENTOVERVNET" = 1
    
  }


  identity {
    type = "SystemAssigned"
  }


  tags = merge(
    var.tags
  )
}

resource "azurerm_private_endpoint" "pe-funcletsencryptdemo" {
  name                = "pe-${azurerm_linux_function_app.funcletsencrypt.name}"
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  subnet_id           = azurerm_subnet.snet-hub-secu.id
  private_service_connection {
    name                           = "psc-pe-${azurerm_linux_function_app.funcletsencrypt.name}"
    private_connection_resource_id = azurerm_linux_function_app.funcletsencrypt.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns-web.id]
  }

  tags = merge(
    var.tags
  )
}

resource "azurerm_log_analytics_workspace" "log-func" {
  name                = "worksppace-func"
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "ins-func" {
  name                = "ins-func"
  location            = azurerm_resource_group.rg-hub-letsencrypt.location
  resource_group_name = azurerm_resource_group.rg-hub-letsencrypt.name
  workspace_id        = azurerm_log_analytics_workspace.log-func.id
  application_type    = "web"
}



