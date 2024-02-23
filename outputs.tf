output "get-agw-pip" {
  description = "Get application public ip"
  value       = "${azurerm_public_ip.pip-appgw.domain_name_label}.${azurerm_public_ip.pip-appgw.location}.cloudapp.azure.com"
}

output "get-blob-url-test" {
  description = "get blob url test"
  value       = "https://${azurerm_storage_account.sa-letsencrypt.name}.blob.core.windows.net/public/.well-known/acme-challenge/index.html"
}