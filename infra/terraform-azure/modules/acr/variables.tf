variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "project_name"        { type = string }
variable "environment"         { type = string }
variable "sku"                 { type = string; default = "Basic" }
variable "tags"                { type = map(string); default = {} }
