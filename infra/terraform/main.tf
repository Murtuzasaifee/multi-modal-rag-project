# Get the default VPC and subnets if not provided
module "vpc" {
  source = "./modules/vpc"

  vpc_id     = var.vpc_id
  subnet_ids  = var.subnet_ids
  aws_region  = var.aws_region
}

# Security groups
module "security_groups" {
  source = "./modules/security_groups"

  vpc_id        = module.vpc.vpc_id
  project_name   = var.project_name
  environment    = var.environment
}

# ECR repositories
module "ecr" {
  source = "./modules/ecr"

  project_name  = var.project_name
  environment   = var.environment
  repositories = {
    app = {
      name = "${var.project_name}/app"
    }
  }
}

# ECS cluster
module "ecs" {
  source = "./modules/ecs"

  cluster_name = var.cluster_name
}

# EFS filesystem with access points
module "efs" {
  source = "./modules/efs"

  project_name       = var.project_name
  environment        = var.environment
  subnet_ids         = module.vpc.subnet_ids
  security_group_id  = module.security_groups.ecs_security_group_id
  create_access_points = true
  access_points = {
    qdrant = {
      path             = "/qdrant"
      posix_user_uid   = 1000
      posix_user_gid   = 1000
      owner_uid        = 1000
      owner_gid        = 1000
      permissions      = "755"
    }
    ollama = {
      path             = "/ollama"
      posix_user_uid   = 0
      posix_user_gid   = 0
      owner_uid        = 0
      owner_gid        = 0
      permissions      = "755"
    }
  }
}

# Secrets Manager
module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  secrets = {
    openai_api_key = {
      name        = "${var.project_name}/openai-api-key"
      description = "OpenAI API key for embeddings and generation"
      }
  }
}

# IAM roles and users
module "iam" {
  source = "./modules/iam"

  project_name         = var.project_name
  environment          = var.environment
  ecr_repository_arns = module.ecr.repository_arns
  efs_filesystem_id   = module.efs.filesystem_id
  aws_region          = var.aws_region
  aws_account_id      = data.aws_caller_identity.current.account_id
}

# CloudWatch log groups
module "logs" {
  source = "./modules/logs"

  project_name  = var.project_name
  log_groups = {
    app = {
      name = "/ecs/${var.project_name}-app"
    }
  }
}

# ECS task definitions
module "task_definitions" {
  source = "./modules/task_definitions"

  project_name        = var.project_name
  environment         = var.environment
  ecr_registry_url    = module.ecr.registry_url
  task_execution_role  = module.iam.task_execution_role_arn
  efs_filesystem_id   = module.efs.filesystem_id
  efs_access_point_ids = module.efs.access_point_ids
  cloudwatch_log_group = module.logs.log_group_names["app"]
  app_cpu             = var.app_cpu
  app_memory          = var.app_memory
  parser_backend      = var.parser_backend
  secret_arns        = module.secrets.secret_arns
  aws_region          = var.aws_region
  aws_account_id      = data.aws_caller_identity.current.account_id
}

# Application Load Balancer
module "alb" {
  source = "./modules/alb"

  count               = var.enable_alb ? 1 : 0
  project_name        = var.project_name
  environment         = var.environment
  subnet_ids          = module.vpc.subnet_ids
  security_group_id   = module.security_groups.alb_security_group_id
  vpc_id             = module.vpc.vpc_id
  health_check_paths  = {
    app = "/health"
  }
}

# ECS services
module "services" {
  source = "./modules/services"

  project_name           = var.project_name
  environment            = var.environment
  cluster_name          = module.ecs.cluster_name
  subnet_ids            = module.vpc.subnet_ids
  security_group_id      = module.security_groups.ecs_security_group_id
  task_definition_arns   = module.task_definitions.task_definition_arns
  target_group_arns     = var.enable_alb ? module.alb[0].target_group_arns : {}
  desired_count          = var.desired_count
  enable_execute_command = true
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}
