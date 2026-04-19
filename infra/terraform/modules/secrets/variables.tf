variable "project_name" {
  description = "Project name"
  type        = string
}

variable "secrets" {
  description = "Map of secrets to create (secret values should be set separately)"
  type = map(object({
    name        = string
    description = string
  }))
}

variable "secret_values" {
  description = "Map of secret values (optional - can be set via AWS CLI)"
  type        = map(map(string))
  default     = {}
}

variable "recovery_window_in_days" {
  description = "Number of days before secret can be deleted"
  type        = number
  default     = 0
}

variable "enable_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = false
}
