# bootstrap/main.tf
#
# PURPOSE: This runs ONCE manually before any other Terraform.
# It creates the S3 bucket and DynamoDB table that all other Terraform
# state will be stored in. You can't store bootstrap's own state remotely
# (the bucket doesn't exist yet), so it uses local state.
#
# Run:
#   cd infra/terraform/bootstrap
#   terraform init
#   terraform apply
#
# After this runs, commit the outputs (bucket name, table name) and
# never run it again unless you're rebuilding from scratch.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Intentionally no remote backend here — chicken-and-egg problem.
  # This is the only Terraform config that uses local state.
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name, used as a prefix for all resources"
  type        = string
  default     = "platform"
}

# ── S3 Bucket for Terraform State ────────────────────────────────────────────
# All workspaces (dev, prod) store their state here under different prefixes.
# Versioning is enabled so you can roll back to a previous state if needed.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project}-terraform-state-${random_id.suffix.hex}"

  # Prevent accidental deletion of the state bucket.
  # To destroy: first set this to false, apply, then destroy.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "${var.project}-terraform-state"
    Purpose = "Terraform remote state storage"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access — state files may contain sensitive data (IPs, ARNs)
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt state at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── DynamoDB Table for State Locking ─────────────────────────────────────────
# Prevents two engineers (or two CI runs) from running terraform apply
# at the same time and corrupting the state file.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # no need to provision capacity for a lock table
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "${var.project}-terraform-locks"
    Purpose = "Terraform state locking"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
# Copy these values into the backend block in ../versions.tf
output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "Paste this into the S3 backend config in versions.tf"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "Paste this into the S3 backend config in versions.tf"
}
