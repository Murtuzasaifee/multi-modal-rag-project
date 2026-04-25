variable "resource_group_name"        { type = string }
variable "location"                   { type = string }
variable "project_name"               { type = string }
variable "environment"                { type = string }
variable "infrastructure_subnet_id"   { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "log_analytics_primary_key"  { type = string; sensitive = true }
variable "acr_login_server"           { type = string }
variable "managed_identity_id"        { type = string }
variable "managed_identity_client_id" { type = string }
variable "key_vault_id"               { type = string }
variable "storage_account_name"       { type = string }
variable "storage_account_key"        { type = string; sensitive = true }
variable "qdrant_share_name"          { type = string }
variable "ollama_share_name"          { type = string }
variable "app_cpu"                    { type = number }
variable "app_memory"                 { type = string }
variable "qdrant_cpu"                 { type = number }
variable "qdrant_memory"              { type = string }
variable "ollama_cpu"                 { type = number }
variable "ollama_memory"              { type = string }
variable "app_min_replicas"           { type = number }
variable "app_max_replicas"           { type = number }
variable "parser_backend"             { type = string }
variable "embedding_provider"         { type = string }
variable "reranker_backend"           { type = string }
variable "tags"                       { type = map(string); default = {} }
