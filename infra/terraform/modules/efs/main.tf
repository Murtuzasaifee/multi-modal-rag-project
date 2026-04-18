resource "aws_efs_file_system" "main" {
  creation_token   = "${var.project_name}-${var.environment}"
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  encrypted  = var.at_rest_encryption != null ? true : false
  kms_key_id = var.at_rest_encryption

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_efs_mount_target" "main" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [var.security_group_id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_efs_access_point" "main" {
  for_each = var.create_access_points ? var.access_points : {}

  file_system_id = aws_efs_file_system.main.id

  posix_user {
    uid = each.value.posix_user_uid
    gid = each.value.posix_user_gid
  }

  root_directory {
    path = each.value.path

    creation_info {
      owner_uid   = each.value.owner_uid
      owner_gid   = each.value.owner_gid
      permissions = each.value.permissions
    }
  }
}

# Wait for mount targets to be ready (null_resource with depends_on)
resource "null_resource" "wait_for_mount_targets" {
  depends_on = [aws_efs_mount_target.main]
}
