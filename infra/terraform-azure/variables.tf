variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix used for all resource names"
  type        = string
  default     = "doc-parser"
}

variable "resource_group_name" {
  description = "Override the auto-generated resource group name"
  type        = string
  default     = null
}

variable "acr_sku" {
  description = "Azure Container Registry SKU (Basic | Standard | Premium)"
  type        = string
  default     = "Basic"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard, or Premium."
  }
}

# ── Container resource sizing ──────────────────────────────────────────────────
# All three containers run as sidecars in a single Container App.
# The sum of cpu/memory must not exceed the Consumption plan maximums:
#   4 vCPU and 8 Gi per Container App.
variable "app_cpu" {
  description = "vCPU allocated to the app container"
  type        = number
  default     = 1.0
}

variable "app_memory" {
  description = "Memory (Gi) allocated to the app container"
  type        = string
  default     = "2.0Gi"
}

variable "qdrant_cpu" {
  description = "vCPU allocated to the qdrant sidecar container"
  type        = number
  default     = 0.5
}

variable "qdrant_memory" {
  description = "Memory (Gi) allocated to the qdrant sidecar container"
  type        = string
  default     = "1.0Gi"
}

variable "ollama_cpu" {
  description = "vCPU allocated to the ollama sidecar container"
  type        = number
  default     = 2.0
}

variable "ollama_memory" {
  description = "Memory (Gi) allocated to the ollama sidecar container"
  type        = string
  default     = "4.0Gi"
}

# ── Scaling ────────────────────────────────────────────────────────────────────
variable "app_min_replicas" {
  description = "Minimum Container App replicas (0 = scale-to-zero)"
  type        = number
  default     = 1
}

variable "app_max_replicas" {
  description = "Maximum Container App replicas"
  type        = number
  default     = 3
}

# ── Application config ─────────────────────────────────────────────────────────
variable "parser_backend" {
  description = "Parser backend: cloud (Z.AI) or ollama (local)"
  type        = string
  default     = "cloud"
  validation {
    condition     = contains(["cloud", "ollama"], var.parser_backend)
    error_message = "parser_backend must be 'cloud' or 'ollama'."
  }
}

variable "embedding_provider" {
  description = "Embedding provider: openai or gemini"
  type        = string
  default     = "openai"
}

variable "reranker_backend" {
  description = "Reranker backend: openai, jina, bge, or qwen"
  type        = string
  default     = "openai"
}

# ── Observability ──────────────────────────────────────────────────────────────
variable "log_retention_days" {
  description = "Log Analytics Workspace retention period in days"
  type        = number
  default     = 30
}

# ── Misc ───────────────────────────────────────────────────────────────────────
variable "tags" {
  description = "Additional tags to merge onto every resource"
  type        = map(string)
  default     = {}
}
