output "repository_urls" {
  description = "Map of repository URLs"
  value       = { for k, v in aws_ecr_repository.repositories : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository ARNs"
  value       = { for k, v in aws_ecr_repository.repositories : k => v.arn }
}

output "registry_url" {
  description = "ECR registry URL"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}
