# main.tf — root module
#
# Wires the EKS and ECR modules together.
# The active Terraform workspace ("dev" or "prod") automatically selects
# the right config from var.eks_config — no Terragrunt needed.
#
# Workflow:
#   terraform workspace select dev   && terraform apply
#   terraform workspace select prod  && terraform apply

locals {
  environment = terraform.workspace  # "dev" or "prod"
  config      = var.eks_config[local.environment]
}

# ── Networking ────────────────────────────────────────────────────────────────
# A minimal VPC with public and private subnets across 2 AZs.
# In a real setup you'd likely extract this into its own module.
# EKS nodes live in private subnets; load balancers live in public subnets.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-${local.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true   # allows nodes in private subnets to reach the internet
  single_nat_gateway = local.environment == "dev" ? true : false  # cost saving in dev

  # Tags required for EKS to discover subnets and provision load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.project}-${local.environment}" = "owned"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${var.project}-${local.environment}" = "owned"
  }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project            = var.project
  environment        = local.environment
  cluster_version    = local.config.cluster_version
  subnet_ids         = module.vpc.private_subnets
  node_instance_type = local.config.node_instance_type
  node_min_size      = local.config.node_min_size
  node_max_size      = local.config.node_max_size
  node_desired_size  = local.config.node_desired_size
}

# ── ECR Repositories ──────────────────────────────────────────────────────────
# One repo per service. The for_each iterates over var.services
# ["api-gateway", "user-service", "order-service"] and creates a module
# instance for each — cleaner than copy-pasting the module block 3 times.
module "ecr" {
  source   = "./modules/ecr"
  for_each = toset(var.services)

  project           = var.project
  environment       = local.environment
  service_name      = each.key
  eks_node_role_arn = module.eks.node_role_arn
}
