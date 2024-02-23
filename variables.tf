variable "location" {
  type    = string
  default = "FranceCentral"
}

variable "projetname" {
  type    = string
  default = "blaletsencrypt"
}

variable "rg-hub" {
  type = map(object({
    name     = string
    location = string
  }))
}

variable "rg-prod" {
  type = map(object({
    name     = string
    location = string
  }))
}


variable "vnet-hub" {
  type = map(object({
    name     = string
    location = string
    rg       = string
    cidr     = list(string)
    subnets = map(object({
      name = string
      cidr = string
    }))
  }))
}

variable "vnet-prod" {
  type = map(object({
    name     = string
    location = string
    rg       = string
    cidr     = list(string)
    subnets = map(object({
      name = string
      cidr = string
    }))
  }))
}

variable "kv-hub" {
  type = map(object({
    name     = string
    location = string
    rg       = string
    sku_name = string
  }))
}

variable "tags" {
  type = map(any)

  default = {
    Owner   = "BLA"
    project = "LetsEncrypt"

  }
}
