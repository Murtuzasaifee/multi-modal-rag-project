# ACR name rules: 5-50 chars, globally unique, alphanumeric only.
resource "azurerm_container_registry" "main" {
  name                = "${replace(var.project_name, "-", "")}${var.environment}acr"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  # Admin credentials disabled
  # CI/CD uses a service principal with AcrPush role.
  admin_enabled = false
  tags          = var.tags
}
