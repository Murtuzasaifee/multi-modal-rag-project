output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "ECS task execution role name"
  value       = aws_iam_role.task_execution.name
}

output "cicd_user_name" {
  description = "CI/CD user name"
  value       = var.create_cicd_user ? aws_iam_user.cicd[0].name : null
}

output "cicd_user_access_key_id" {
  description = "CI/CD user access key ID"
  value       = var.create_cicd_user ? aws_iam_access_key.cicd[0].id : null
  sensitive   = true
}

output "cicd_user_secret_key" {
  description = "CI/CD user secret access key"
  value       = var.create_cicd_user ? aws_iam_access_key.cicd[0].secret : null
  sensitive   = true
}

output "admin_user_name" {
  description = "Admin user name"
  value       = var.create_admin_user ? aws_iam_user.admin[0].name : null
}
