output "filesystem_id" {
  description = "EFS filesystem ID"
  value       = aws_efs_file_system.main.id
}

output "filesystem_arn" {
  description = "EFS filesystem ARN"
  value       = aws_efs_file_system.main.arn
}

output "access_point_ids" {
  description = "Map of access point IDs"
  value       = { for k, v in aws_efs_access_point.main : k => v.id }
}

output "access_point_arns" {
  description = "Map of access point ARNs"
  value       = { for k, v in aws_efs_access_point.main : k => v.arn }
}
