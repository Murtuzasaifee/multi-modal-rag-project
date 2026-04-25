# ── Container Apps Environment ─────────────────────────────────────────────────
# VNet-integrated environment provides private networking for the containers
# while the external load balancer handles public HTTPS traffic (replaces ALB).
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.project_name}-${var.environment}-cae"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  infrastructure_subnet_id   = var.infrastructure_subnet_id
  tags                       = var.tags
}

# ── Azure File Share mounts ────────────────────────────────────────────────────
# These environment-level storage entries mirror EFS access points from AWS.

resource "azurerm_container_app_environment_storage" "qdrant" {
  name                         = "qdrant-storage"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = var.storage_account_name
  share_name                   = var.qdrant_share_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "ollama" {
  name                         = "ollama-storage"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = var.storage_account_name
  share_name                   = var.ollama_share_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
}

# ── Key Vault secrets ──────────────────────────────────────────────────────────
# Placeholder values; set real values post-deploy:
#   az keyvault secret set --vault-name <name> --name openai-api-key --value sk-...
# ignore_changes prevents Terraform from overwriting manually set values.

resource "azurerm_key_vault_secret" "openai_api_key" {
  name         = "openai-api-key"
  value        = "placeholder-set-via-cli"
  key_vault_id = var.key_vault_id

  lifecycle {
    ignore_changes = [value]
  }
}

# ── Main Container App ─────────────────────────────────────────────────────────
# All three containers (app, qdrant, ollama) run as sidecars inside one Container
# App, exactly mirroring the single ECS task definition on AWS.  Because they
# share a network namespace, the existing env vars (localhost:6333, localhost:11434)
# require no modification.
resource "azurerm_container_app" "main" {
  name                         = "${var.project_name}-app"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  # User-assigned identity for ACR pull and Key Vault secret access
  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # Pull images from ACR using the managed identity (no admin credentials needed)
  registry {
    server   = var.acr_login_server
    identity = var.managed_identity_id
  }

  # Key Vault-backed secret — versionless_id always resolves the latest version
  secret {
    name                = "openai-api-key"
    key_vault_secret_id = azurerm_key_vault_secret.openai_api_key.versionless_id
    identity            = var.managed_identity_id
  }

  template {
    min_replicas = var.app_min_replicas
    max_replicas = var.app_max_replicas

    # ── app container ──────────────────────────────────────────────────────────
    container {
      name   = "app"
      image  = "${var.acr_login_server}/${var.project_name}/app:latest"
      cpu    = var.app_cpu
      memory = var.app_memory

      env {
        name  = "EMBEDDING_PROVIDER"
        value = var.embedding_provider
      }
      env {
        name  = "RERANKER_BACKEND"
        value = var.reranker_backend
      }
      # qdrant and ollama share the network namespace (localhost) — no URL changes needed
      env {
        name  = "QDRANT_URL"
        value = "http://localhost:6333"
      }
      env {
        name  = "PARSER_BACKEND"
        value = var.parser_backend
      }
      env {
        name  = "OLLAMA_BASE_URL"
        value = "http://localhost:11434"
      }
      env {
        name        = "OPENAI_API_KEY"
        secret_name = "openai-api-key"
      }

      # Startup probe: generous window so qdrant/ollama can initialise first
      startup_probe {
        transport               = "HTTP"
        path                    = "/health"
        port                    = 8000
        interval_seconds        = 10
        failure_count_threshold = 30 # 5-minute window
        timeout                 = 5
      }

      readiness_probe {
        transport               = "HTTP"
        path                    = "/health"
        port                    = 8000
        initial_delay           = 10
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 5
      }

      liveness_probe {
        transport               = "HTTP"
        path                    = "/health"
        port                    = 8000
        initial_delay           = 30
        interval_seconds        = 30
        failure_count_threshold = 3
        timeout                 = 5
      }
    }

    # ── qdrant sidecar ─────────────────────────────────────────────────────────
    container {
      name   = "qdrant"
      image  = "qdrant/qdrant:v1.17.1"
      cpu    = var.qdrant_cpu
      memory = var.qdrant_memory

      env {
        name  = "QDRANT__STORAGE__SKIP_FILESYNC_ON_OPEN"
        value = "true"
      }

      volume_mounts {
        name = "qdrant-data"
        path = "/qdrant/storage"
      }
    }

    # ── ollama sidecar ─────────────────────────────────────────────────────────
    container {
      name   = "ollama"
      image  = "ollama/ollama:latest"
      cpu    = var.ollama_cpu
      memory = var.ollama_memory

      env {
        name  = "OLLAMA_HOST"
        value = "0.0.0.0"
      }

      volume_mounts {
        name = "ollama-models"
        path = "/root/.ollama"
      }
    }

    # Azure File Share volumes (replaces EFS volumes from AWS task definition)
    volume {
      name         = "qdrant-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.qdrant.name
    }

    volume {
      name         = "ollama-models"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.ollama.name
    }
  }

  # External HTTPS ingress — replaces the AWS Application Load Balancer.
  # Azure Container Apps terminates TLS and forwards HTTP to the app on port 8000.
  ingress {
    external_enabled           = true
    target_port                = 8000
    transport                  = "http"
    allow_insecure_connections = false

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_container_app_environment_storage.qdrant,
    azurerm_container_app_environment_storage.ollama,
  ]
}
