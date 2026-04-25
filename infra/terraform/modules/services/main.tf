locals {
  # Service configurations
  services = {
    app = {
      task_definition = var.task_definition_arns["app"]
      target_group_arn = try(var.target_group_arns["app"], null)
      container_name   = "app"
      container_port  = 8000
    }
  }
}

resource "aws_ecs_service" "main" {
  for_each = local.services

  name            = "${var.project_name}-${each.key}"
  cluster         = var.cluster_name
  task_definition = each.value.task_definition
  desired_count   = var.desired_count
  launch_type     = var.launch_type
  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.subnet_ids
    security_groups   = [var.security_group_id]
    assign_public_ip = var.assign_public_ip
  }

  # Load balancer configuration (if target group provided)
  dynamic "load_balancer" {
    for_each = each.value.target_group_arn != null ? [1] : []
    content {
      target_group_arn = each.value.target_group_arn
      container_name   = each.value.container_name
      container_port  = each.value.container_port
    }
  }

  # Deployment configuration
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = var.enable_circuit_breaker
    rollback = var.enable_circuit_breaker
  }

  # Health check grace period
  health_check_grace_period_seconds = var.enable_health_check_grace_period ? var.health_check_grace_period_seconds : null

  # Service tags
  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.environment
  }

  # Ignore changes to desired_count to allow manual scaling
  lifecycle {
    ignore_changes = [desired_count]
  }
}
