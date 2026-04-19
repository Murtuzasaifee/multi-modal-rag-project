output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = module.vpc.subnet_ids
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = module.security_groups.alb_security_group_id
}

output "ecs_security_group_id" {
  description = "ECS security group ID"
  value       = module.security_groups.ecs_security_group_id
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "efs_filesystem_id" {
  description = "EFS filesystem ID"
  value       = module.efs.filesystem_id
}

output "efs_access_point_ids" {
  description = "EFS access point IDs"
  value       = module.efs.access_point_ids
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.iam.task_execution_role_arn
}

output "cicd_user_access_key_id" {
  description = "CI/CD user access key ID"
  value       = module.iam.cicd_user_access_key_id
  sensitive   = true
}

output "cicd_user_secret_key" {
  description = "CI/CD user secret access key"
  value       = module.iam.cicd_user_secret_key
  sensitive   = true
}

output "task_definition_arns" {
  description = "ECS task definition ARNs"
  value       = module.task_definitions.task_definition_arns
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = try(module.alb[0].alb_dns_name, null)
}

output "alb_public_url" {
  description = "ALB public URL"
  value       = try("http://${module.alb[0].alb_dns_name}", null)
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route53 alias"
  value       = try(module.alb[0].alb_zone_id, null)
}

output "service_arns" {
  description = "ECS service ARNs"
  value       = module.services.service_arns
}

output "secret_arns" {
  description = "Secrets Manager secret ARNs"
  value       = module.secrets.secret_arns
  sensitive   = true
}
