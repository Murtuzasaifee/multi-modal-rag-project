variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS services"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet must be provided."
  }
}

variable "security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "task_definition_arns" {
  description = "Map of task definition ARNs"
  type        = map(string)
}

variable "target_group_arns" {
  description = "Map of target group ARNs for load balancers"
  type        = map(string)
  default     = {}
}

variable "desired_count" {
  description = "Desired number of tasks for each service"
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be 0 or greater."
  }
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for container access"
  type        = bool
  default     = true
}

variable "launch_type" {
  description = "ECS launch type (FARGATE or EC2)"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "launch_type must be either 'FARGATE' or 'EC2'."
  }
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
  default     = true
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percent during deployment"
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Maximum percent during deployment"
  type        = number
  default     = 200
}

variable "enable_circuit_breaker" {
  description = "Enable deployment circuit breaker"
  type        = bool
  default     = true
}

variable "enable_health_check_grace_period" {
  description = "Enable health check grace period"
  type        = bool
  default     = true
}

variable "health_check_grace_period_seconds" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}
