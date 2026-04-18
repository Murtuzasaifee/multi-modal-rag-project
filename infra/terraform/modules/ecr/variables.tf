variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "repositories" {
  description = "Map of repositories to create"
  type = map(object({
    name = string
  }))

  validation {
    condition     = can(length(keys(var.repositories)))
    error_message = "At least one repository must be defined."
  }
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}
