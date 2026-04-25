resource "aws_secretsmanager_secret" "main" {
  for_each = var.secrets

  name                    = each.value.name
  description             = each.value.description
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Project = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "main" {
  for_each = {
    for k, v in var.secret_values : k => v
    if contains(keys(var.secrets), k)
  }

  secret_id     = aws_secretsmanager_secret.main[each.key].id
  secret_string = jsonencode(each.value)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Rotation configuration (requires Lambda function - not implemented here)
resource "aws_secretsmanager_secret_rotation" "main" {
  for_each = var.enable_rotation ? var.secrets : {}

  secret_id           = aws_secretsmanager_secret.main[each.key].id
  rotation_lambda_arn  = "" # Set this to a Lambda function ARN for rotation
  rotation_rules {
    automatically_after_days = 30
  }
}
