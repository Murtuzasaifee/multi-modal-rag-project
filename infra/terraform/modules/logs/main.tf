resource "aws_cloudwatch_log_group" "main" {
  for_each = var.log_groups

  name              = each.value.name
  retention_in_days  = var.retention_in_days
  kms_key_id        = var.kms_key_id

  tags = {
    Project = var.project_name
  }
}
