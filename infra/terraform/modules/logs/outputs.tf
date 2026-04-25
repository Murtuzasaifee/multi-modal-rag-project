output "log_group_names" {
  description = "Map of log group names"
  value       = { for k, v in aws_cloudwatch_log_group.main : k => v.name }
}

output "log_group_arns" {
  description = "Map of log group ARNs"
  value       = { for k, v in aws_cloudwatch_log_group.main : k => v.arn }
}
