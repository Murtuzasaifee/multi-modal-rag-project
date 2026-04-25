terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Backend config is supplied via -backend-config flags or ARM_* env vars.
  # Run infra/setup-backend-azure.sh first to create the storage account.
  backend "azurerm" {}
}
