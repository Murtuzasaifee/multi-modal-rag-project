variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alb_ingress_cidr" {
  description = "CIDR block allowed for ALB ingress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alb_port" {
  description = "Port exposed by ALB"
  type        = number
  default     = 80
}

variable "app_port" {
  description = "FastAPI application port"
  type        = number
  default     = 8000
}

variable "efs_port" {
  description = "EFS/NFS port"
  type        = number
  default     = 2049
}
