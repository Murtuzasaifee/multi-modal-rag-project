variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ALB"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets are required for ALB."
  }
}

variable "security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "health_check_paths" {
  description = "Map of service health check paths"
  type        = map(string)
  default     = {}
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Health check healthy threshold"
  type        = number
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  description = "Health check unhealthy threshold"
  type        = number
  default     = 3
}

variable "health_check_matcher" {
  description = "Health check matcher"
  type        = string
  default     = "200"
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 3600
    error_message = "idle_timeout must be between 1 and 3600 seconds."
  }
}

variable "drop_invalid_header_fields" {
  description = "Drop invalid header fields"
  type        = bool
  default     = true
}

variable "deregistration_delay" {
  description = "Deregistration delay in seconds"
  type        = number
  default     = 300
}
