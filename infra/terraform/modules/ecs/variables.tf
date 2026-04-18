variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}
