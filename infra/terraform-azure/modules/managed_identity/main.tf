resource "azurerm_user_assigned_identity" "main" {
  name                = "${var.project_name}-${var.environment}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Allow the identity to pull images from ACR (used by Container Apps).
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Allow the identity to read secrets from Key Vault.
resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_user_assigned_identity.main.tenant_id
  object_id    = azurerm_user_assigned_identity.main.principal_id

  secret_permissions = ["Get", "List"]
}
