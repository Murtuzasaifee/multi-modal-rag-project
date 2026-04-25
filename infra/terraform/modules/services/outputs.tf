output "service_arns" {
  description = "Map of service ARNs"
  value       = { for k, v in aws_ecs_service.main : k => v.id }
}

output "service_names" {
  description = "Map of service names"
  value       = { for k, v in aws_ecs_service.main : k => v.name }
}

output "service_ids" {
  description = "Map of service IDs"
  value       = { for k, v in aws_ecs_service.main : k => v.id }
}
