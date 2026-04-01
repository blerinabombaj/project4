# modules/ecr/main.tf
#
# Creates one ECR (Elastic Container Registry) repository per service.
# ECR is AWS's private Docker registry — your CI/CD pipeline pushes
# images here, and EKS nodes pull from here at deploy time.

resource "aws_ecr_repository" "this" {
  name                 = "${var.project}-${var.environment}-${var.service_name}"
  image_tag_mutability = "MUTABLE"  # allows overwriting tags like "dev-latest"

  # Enable Trivy-compatible image scanning on every push.
  # Findings appear in the ECR console and can be queried via API.
  # Your CI pipeline (later) will fail the build if CRITICAL CVEs are found.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Service     = var.service_name
    Environment = var.environment
  }
}

# ── Lifecycle Policy ──────────────────────────────────────────────────────────
# ECR storage costs money. Without a lifecycle policy, every image push
# accumulates forever. This keeps only the last 10 untagged images
# (intermediate layers) and the last 20 tagged releases.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images older than 10 kept"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "dev-", "prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── Repository Policy ─────────────────────────────────────────────────────────
# Allows the EKS node IAM role to pull images.
# Without this, EKS nodes get 403 errors trying to pull your images.
resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSNodePull"
        Effect = "Allow"
        Principal = {
          AWS = var.eks_node_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
