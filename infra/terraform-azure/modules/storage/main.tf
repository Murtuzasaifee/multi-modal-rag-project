# Storage account name: 3-24 chars, lowercase alphanumeric, globally unique.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "azurerm_storage_account" "main" {
  name                     = "${replace(var.project_name, "-", "")}${var.environment}${random_id.suffix.hex}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_share" "qdrant" {
  name               = "qdrant-data"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 100 # GiB
}

resource "azurerm_storage_share" "ollama" {
  name               = "ollama-models"
  storage_account_id = azurerm_storage_account.main.id
  quota              = 200 # GiB
}
