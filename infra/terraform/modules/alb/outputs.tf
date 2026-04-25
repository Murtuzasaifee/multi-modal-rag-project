output "alb_id" {
  description = "ALB ID"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route53 alias"
  value       = aws_lb.main.zone_id
}

output "target_group_arns" {
  description = "Map of target group ARNs"
  value       = { for k, v in aws_lb_target_group.main : k => v.arn }
}

output "target_group_ids" {
  description = "Map of target group IDs"
  value       = { for k, v in aws_lb_target_group.main : k => v.id }
}

output "listener_arns" {
  description = "Map of listener ARNs"
  value       = {
    http = aws_lb_listener.http.arn
  }
}
