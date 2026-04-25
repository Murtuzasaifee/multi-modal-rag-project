output "account_name" {
  value = azurerm_storage_account.main.name
}

output "account_key" {
  value     = azurerm_storage_account.main.primary_access_key
  sensitive = true
}

output "qdrant_share_name" {
  value = azurerm_storage_share.qdrant.name
}

output "ollama_share_name" {
  value = azurerm_storage_share.ollama.name
}
