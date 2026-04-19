# ECS Task Execution Role (assumed by Fargate)
resource "aws_iam_role" "task_execution" {
  name_prefix = "${var.project_name}-ecs-task-exec-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

# Attach AWS-managed policy for ECR and CloudWatch
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy: Secrets Manager read
resource "aws_iam_role_policy" "secrets_manager_read" {
  name = "secrets-manager-read"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/*"
      }
    ]
  })
}

# Inline policy: EFS mount
resource "aws_iam_role_policy" "efs_mount" {
  name = "efs-mount"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = "arn:aws:elasticfilesystem:${var.aws_region}:${var.aws_account_id}:file-system/${var.efs_filesystem_id}"
      }
    ]
  })
}

# Inline policy: ECS Exec (for debugging)
resource "aws_iam_role_policy" "ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# CI/CD User (for GitHub Actions)
resource "aws_iam_user" "cicd" {
  count = var.create_cicd_user ? 1 : 0

  name = "${var.project_name}-cicd"
  path        = "/cicd/"

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_access_key" "cicd" {
  count = var.create_cicd_user ? 1 : 0

  user = aws_iam_user.cicd[0].name
}

resource "aws_iam_user_policy" "cicd" {
  count = var.create_cicd_user ? 1 : 0

  name_prefix = "${var.project_name}-cicd-policy-"
  user        = aws_iam_user.cicd[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [for v in var.ecr_repository_arns : v]
      },
      {
        Sid    = "ECSDeployServices"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "elasticloadbalancing:DescribeLoadBalancers"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSWaitForStable"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      }
    ]
  })
}

# Admin User (optional - for manual operations)
resource "aws_iam_user" "admin" {
  count = var.create_admin_user ? 1 : 0

  name = "${var.project_name}-admin"
  path        = "/admin/"

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_access_key" "admin" {
  count = var.create_admin_user ? 1 : 0

  user = aws_iam_user.admin[0].name
}

resource "aws_iam_user_policy" "admin" {
  count = var.create_admin_user ? 1 : 0

  name_prefix = "${var.project_name}-admin-policy-"
  user        = aws_iam_user.admin[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRFullAccess"
        Effect = "Allow"
        Action = ["ecr:*"]
        Resource = [
          for v in var.ecr_repository_arns : v
        ]
      },
      {
        Sid    = "ECSFullAccess"
        Effect = "Allow"
        Action = ["ecs:*"]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerDocParser"
        Effect = "Allow"
        Action = ["secretsmanager:*"]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project_name}/*"
      },
      {
        Sid    = "ECSExec"
        Effect = "Allow"
        Action = ["ssmmessages:*"]
        Resource = "*"
      }
    ]
  })
}
