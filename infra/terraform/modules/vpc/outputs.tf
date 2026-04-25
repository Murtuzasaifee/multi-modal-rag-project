output "vpc_id" {
  description = "VPC ID"
  value       = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = length(coalesce(var.subnet_ids, [])) > 0 ? var.subnet_ids : slice(data.aws_subnets.default[0].ids, 0, 2)
}
