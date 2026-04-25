output "secret_arns" {
  description = "Map of secret ARNs"
  value       = { for k, v in aws_secretsmanager_secret.main : k => v.arn }
  sensitive   = true
}

output "secret_names" {
  description = "Map of secret names"
  value       = { for k, v in aws_secretsmanager_secret.main : k => v.name }
}
