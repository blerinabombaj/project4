# versions.tf
#
# Defines the required Terraform version, provider versions, and the
# remote backend where state is stored.
#
# The backend block is static — it cannot use variables. So the bucket
# name and table name from bootstrap are hardcoded here after running bootstrap.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }

  # Remote backend — state is stored in S3, locked with DynamoDB.
  # Terraform workspaces automatically prefix state paths:
  #   dev  → s3://bucket/env:/dev/platform/terraform.tfstate
  #   prod → s3://bucket/env:/prod/platform/terraform.tfstate
  backend "s3" {
    bucket         = "platform-terraform-state-REPLACE_WITH_BOOTSTRAP_OUTPUT"
    key            = "platform/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "platform-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = terraform.workspace   # "dev" or "prod" automatically
      ManagedBy   = "terraform"
    }
  }
}
