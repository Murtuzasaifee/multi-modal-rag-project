variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key_id" {
  description = "AWS access key ID (optional - overrides profile/env)"
  type        = string
  default     = null
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key (optional - overrides profile/env)"
  type        = string
  default     = null
  sensitive   = true
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "doc-parser"
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "doc-parser-cluster"
}

variable "vpc_id" {
  description = "VPC ID (uses default VPC if not specified)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks and ALB (comma-separated)"
  type        = list(string)
  default     = []
}

variable "app_cpu" {
  description = "CPU units for app task"
  type        = number
  default     = 2048
}

variable "app_memory" {
  description = "Memory for app task in MB"
  type        = number
  default     = 16384
}

variable "desired_count" {
  description = "Desired number of tasks for each service"
  type        = number
  default     = 1
}

variable "enable_alb" {
  description = "Enable ALB creation"
  type        = bool
  default     = true
}

variable "parser_backend" {
  description = "Parser backend: cloud or ollama"
  type        = string
  default     = "ollama"

  validation {
    condition     = contains(["cloud", "ollama"], var.parser_backend)
    error_message = "parser_backend must be either 'cloud' or 'ollama'."
  }
}

variable "app_port" {
  description = "FastAPI application port"
  type        = number
  default     = 8000
}
