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

  #LYON3
  subscription_id = "eccd9223-bed6-4917-80d9-df26ebcab422"
  client_id       = "e4fe5f69-5528-44ce-8754-e270f2a363cb"
  client_secret   = "ODt8Q~EN60rb5_0TZCJ18~_ndqNf.jj99GCGbbim"
  tenant_id       = "f16e2aeb-1014-43ec-be82-abcdfa6e94b7"
}

provider "azurerm" {
  features {}

  #LYON2
  alias           = "prod"
  subscription_id = "b2916dd2-5675-43c3-834b-5feff79458ee"
  client_id       = "e4fe5f69-5528-44ce-8754-e270f2a363cb"
  client_secret   = "ODt8Q~EN60rb5_0TZCJ18~_ndqNf.jj99GCGbbim"
  tenant_id       = "f16e2aeb-1014-43ec-be82-abcdfa6e94b7"
}
