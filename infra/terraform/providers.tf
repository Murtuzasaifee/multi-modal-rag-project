provider "aws" {
  region = var.aws_region

  # Priority: 1) Explicit credentials, 2) Profile, 3) Environment/Config
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
