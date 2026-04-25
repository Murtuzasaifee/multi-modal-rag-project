variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecr_registry_url" {
  description = "ECR registry URL"
  type        = string
}

variable "task_execution_role" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "efs_filesystem_id" {
  description = "EFS filesystem ID"
  type        = string
}

variable "efs_access_point_ids" {
  description = "EFS access point IDs"
  type        = map(string)
}

variable "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  type        = string
}

variable "app_cpu" {
  description = "CPU units for app task"
  type        = number
  default     = 2048
}

variable "app_memory" {
  description = "Memory for app task in MB"
  type        = number
  default     = 8192
}

variable "parser_backend" {
  description = "Parser backend: cloud or ollama"
  type        = string
  default     = "ollama"
}

variable "secret_arns" {
  description = "Secret ARNs for injection"
  type        = map(string)
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "qdrant_image" {
  description = "Qdrant Docker image"
  type        = string
  default     = "qdrant/qdrant:v1.17.1"
}

variable "ollama_image" {
  description = "Ollama Docker image"
  type        = string
  default     = "ollama/ollama:latest"
}

variable "app_port" {
  description = "FastAPI application port"
  type        = number
  default     = 8000
}

variable "qdrant_port" {
  description = "Qdrant port"
  type        = number
  default     = 6333
}

variable "ollama_port" {
  description = "Ollama port"
  type        = number
  default     = 11434
}

variable "enable_ollama_essential" {
  description = "Make Ollama container essential (restart task if it fails)"
  type        = bool
  default     = true
}
