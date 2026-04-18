data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "repositories" {
  for_each = var.repositories

  name                 = each.value.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = {
    Environment = var.environment
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Lifecycle policy to keep only last 20 images
resource "aws_ecr_lifecycle_policy" "repositories" {
  for_each = var.repositories

  repository = aws_ecr_repository.repositories[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
