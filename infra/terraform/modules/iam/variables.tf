variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs for CI/CD permissions"
  type        = map(string)
}

variable "efs_filesystem_id" {
  description = "EFS filesystem ID for task execution role"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "create_cicd_user" {
  description = "Create CI/CD IAM user"
  type        = bool
  default     = true
}

variable "create_admin_user" {
  description = "Create admin IAM user"
  type        = bool
  default     = false
}
