locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.project_name}-${var.environment}-rg")

  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }, var.tags)
}

module "resource_group" {
  source = "./modules/resource_group"

  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

module "networking" {
  source = "./modules/networking"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  project_name        = var.project_name
  environment         = var.environment
  tags                = local.common_tags
}

module "acr" {
  source = "./modules/acr"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  project_name        = var.project_name
  environment         = var.environment
  sku                 = var.acr_sku
  tags                = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  project_name        = var.project_name
  environment         = var.environment
  tags                = local.common_tags
}

module "key_vault" {
  source = "./modules/key_vault"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  project_name        = var.project_name
  environment         = var.environment
  tags                = local.common_tags
}

module "log_analytics" {
  source = "./modules/log_analytics"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  project_name        = var.project_name
  environment         = var.environment
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

module "managed_identity" {
  source = "./modules/managed_identity"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  project_name        = var.project_name
  environment         = var.environment
  acr_id              = module.acr.id
  key_vault_id        = module.key_vault.id
  tags                = local.common_tags
}

module "container_apps" {
  source = "./modules/container_apps"

  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  project_name               = var.project_name
  environment                = var.environment
  infrastructure_subnet_id   = module.networking.container_apps_subnet_id
  log_analytics_workspace_id = module.log_analytics.workspace_id
  log_analytics_primary_key  = module.log_analytics.primary_shared_key
  acr_login_server           = module.acr.login_server
  managed_identity_id        = module.managed_identity.id
  managed_identity_client_id = module.managed_identity.client_id
  key_vault_id               = module.key_vault.id
  storage_account_name       = module.storage.account_name
  storage_account_key        = module.storage.account_key
  qdrant_share_name          = module.storage.qdrant_share_name
  ollama_share_name          = module.storage.ollama_share_name
  app_cpu                    = var.app_cpu
  app_memory                 = var.app_memory
  qdrant_cpu                 = var.qdrant_cpu
  qdrant_memory              = var.qdrant_memory
  ollama_cpu                 = var.ollama_cpu
  ollama_memory              = var.ollama_memory
  app_min_replicas           = var.app_min_replicas
  app_max_replicas           = var.app_max_replicas
  parser_backend             = var.parser_backend
  embedding_provider         = var.embedding_provider
  reranker_backend           = var.reranker_backend
  tags                       = local.common_tags
}
