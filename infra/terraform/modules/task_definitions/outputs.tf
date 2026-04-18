output "task_definition_arns" {
  description = "Map of task definition ARNs"
  value       = {
    app = aws_ecs_task_definition.app.arn
  }
}

output "task_definition_names" {
  description = "Map of task definition names"
  value       = {
    app = aws_ecs_task_definition.app.family
  }
}
