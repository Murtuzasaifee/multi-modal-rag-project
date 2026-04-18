terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "doc-parser-terraform-state"
    key    = "infra/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}
