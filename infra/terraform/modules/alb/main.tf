resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.subnet_ids
  security_groups    = [var.security_group_id]

  enable_http2                = true
  drop_invalid_header_fields  = var.drop_invalid_header_fields
  idle_timeout               = var.idle_timeout

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "main" {
  for_each = var.health_check_paths

  name_prefix = "${each.key}-"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value
    port                = "traffic-port"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    matcher             = var.health_check_matcher
  }

  deregistration_delay = var.deregistration_delay

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = false
  }

  tags = {
    Name = "${var.project_name}-${each.key}"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "404"
      message_body = "Not Found"
    }
  }

  tags = {
    Name = "${var.project_name}-http-listener"
  }
}

# Forward rules for each target group
resource "aws_lb_listener_rule" "forward" {
  for_each = var.health_check_paths

  listener_arn = aws_lb_listener.http.arn
  priority     = index(keys(var.health_check_paths), each.key) + 10

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[each.key].arn
  }

  depends_on = [aws_lb_target_group.main]
}
