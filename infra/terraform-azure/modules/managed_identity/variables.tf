variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "project_name"        { type = string }
variable "environment"         { type = string }
variable "acr_id"              { type = string }
variable "key_vault_id"        { type = string }
variable "tags"                { type = map(string); default = {} }
