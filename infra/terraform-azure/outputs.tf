output "resource_group_name" {
  description = "Resource group containing all project resources"
  value       = module.resource_group.name
}

output "acr_login_server" {
  description = "Azure Container Registry login server (set as ACR_LOGIN_SERVER secret)"
  value       = module.acr.login_server
}

output "acr_name" {
  description = "Azure Container Registry name (set as ACR_NAME secret)"
  value       = module.acr.name
}

output "key_vault_uri" {
  description = "Key Vault URI — use to set secrets: az keyvault secret set --vault-name ..."
  value       = module.key_vault.vault_uri
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = module.key_vault.name
}

output "storage_account_name" {
  description = "Storage account holding Azure File Shares for qdrant and ollama"
  value       = module.storage.account_name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = module.log_analytics.workspace_id
}

output "managed_identity_client_id" {
  description = "User-assigned managed identity client ID"
  value       = module.managed_identity.client_id
}

output "container_app_environment_id" {
  description = "Container Apps Environment resource ID"
  value       = module.container_apps.environment_id
}

output "container_app_name" {
  description = "Container App name (set as CONTAINER_APP_NAME secret)"
  value       = module.container_apps.app_name
}

output "container_app_fqdn" {
  description = "Public FQDN of the doc-parser Container App"
  value       = module.container_apps.app_fqdn
}

output "container_app_url" {
  description = "Full HTTPS URL for the running service"
  value       = "https://${module.container_apps.app_fqdn}"
}
