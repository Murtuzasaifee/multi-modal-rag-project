data "azurerm_client_config" "current" {}

# Key Vault name: 3-24 chars, alphanumeric + hyphens, globally unique.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "azurerm_key_vault" "main" {
  name                       = "${var.project_name}-${var.environment}-kv-${random_id.suffix.hex}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # enable in production
  tags                       = var.tags
}

# Grant the Terraform executor (SP or interactive user) full secret management.
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "Set", "List", "Delete", "Purge", "Recover"]
}
