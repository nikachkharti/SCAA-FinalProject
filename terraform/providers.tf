terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # default_tags are added automatically to EVERY resource that supports tags.
  # This is the "proper tagging" best practice - you write it once.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
      Repository  = var.repository_url
      CostCenter  = "scaa-devops-course"
    }
  }
}