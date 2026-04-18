variable "vpc_id" {
  description = "VPC ID (uses default VPC if null)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs (uses default subnets if empty or null)"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
