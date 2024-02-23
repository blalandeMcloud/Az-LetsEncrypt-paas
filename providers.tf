# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.91.0"
    }
  }
}


provider "azurerm" {
  features {}

  #SUB HUB
  subscription_id = "xxxxx"
  client_id       = "xxxxx"
  client_secret   = "xxxxx"
  tenant_id       = "xxxxx"
}

provider "azurerm" {
  features {}

  #SUB PROD
  alias           = "prod"
 subscription_id = "xxxxx"
  client_id       = "xxxxx"
  client_secret   = "xxxxx"
  tenant_id       = "xxxxx"
}
