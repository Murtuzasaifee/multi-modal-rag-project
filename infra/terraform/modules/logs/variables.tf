variable "project_name" {
  description = "Project name"
  type        = string
}

variable "log_groups" {
  description = "Map of log groups to create"
  type = map(object({
    name = string
  }))

  validation {
    condition     = can(length(keys(var.log_groups)))
    error_message = "At least one log group must be defined."
  }
}

variable "retention_in_days" {
  description = "Log retention in days (0 for never expire)"
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.retention_in_days)
    error_message = "retention_in_days must be one of: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653"
  }
}

variable "kms_key_id" {
  description = "KMS key ID for log encryption (null for default)"
  type        = string
  default     = null
}
