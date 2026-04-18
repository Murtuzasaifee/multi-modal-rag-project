locals {
  secret_refs = {
    for k, v in var.secret_arns : k => "${v}:${k}::"
  }
}

# App Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory
  execution_role_arn       = var.task_execution_role
  task_role_arn            = var.task_execution_role

  # Volumes (EFS)
  volume {
    name = "qdrant-data"

    efs_volume_configuration {
      file_system_id     = var.efs_filesystem_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.efs_access_point_ids["qdrant"]
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "ollama-models"

    efs_volume_configuration {
      file_system_id     = var.efs_filesystem_id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = var.efs_access_point_ids["ollama"]
        iam             = "ENABLED"
      }
    }
  }

  # Container definitions
  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${var.ecr_registry_url}/${var.project_name}/app:latest"
      essential = true
      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      # Environment variables
      environment = [
        {
          name  = "EMBEDDING_PROVIDER"
          value = "openai"
        },
        {
          name  = "RERANKER_BACKEND"
          value = "openai"
        },
        {
          name  = "QDRANT_URL"
          value = "http://localhost:${var.qdrant_port}"
        },
        {
          name  = "PARSER_BACKEND"
          value = var.parser_backend
        },
        {
          name  = "OLLAMA_BASE_URL"
          value = "http://localhost:${var.ollama_port}"
        }
      ]

      # Secrets (only inject those that exist)
      # Z.AI API key only for cloud backend - ollama backend doesn't need it

      secrets = [
        {
          name      = "OPENAI_API_KEY"
          valueFrom = local.secret_refs["openai_api_key"]
        }
      ]

      # CloudWatch logging
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.cloudwatch_log_group
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "app"
        }
      }

      # Health check
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.app_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Container dependencies
      dependsOn = [
        {
          containerName = "qdrant"
          condition     = "HEALTHY"
        },
        {
          containerName = "ollama"
          condition     = "START"
        }
      ]
    },
    {
      name      = "qdrant"
      image     = var.qdrant_image
      essential = true
      portMappings = [
        {
          containerPort = var.qdrant_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "QDRANT__STORAGE__SKIP_FILESYNC_ON_OPEN"
          value = "true"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "qdrant-data"
          containerPath = "/qdrant/storage"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.cloudwatch_log_group
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "qdrant"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "bash -c ':> /dev/tcp/127.0.0.1/${var.qdrant_port}' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name      = "ollama"
      image     = var.ollama_image
      essential = var.enable_ollama_essential
      portMappings = [
        {
          containerPort = var.ollama_port
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "ollama-models"
          containerPath = "/root/.ollama"
          readOnly      = false
        }
      ]

      environment = [
        {
          name  = "OLLAMA_HOST"
          value = "0.0.0.0"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.cloudwatch_log_group
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ollama"
        }
      }
    }
  ])
}
