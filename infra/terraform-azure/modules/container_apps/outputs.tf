output "environment_id" {
  description = "Container Apps Environment resource ID"
  value       = azurerm_container_app_environment.main.id
}

output "app_name" {
  description = "Container App name"
  value       = azurerm_container_app.main.name
}

output "app_fqdn" {
  description = "Public FQDN assigned by Azure Container Apps ingress"
  value       = azurerm_container_app.main.ingress[0].fqdn
}
