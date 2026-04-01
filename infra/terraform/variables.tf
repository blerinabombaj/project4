# variables.tf
#
# All inputs are declared here. Actual values live in terraform.tfvars.
# Sensitive values (passwords, tokens) should never be in tfvars —
# pass them via environment variables: TF_VAR_my_secret=value

variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name — used as a prefix on all resource names"
  type        = string
  default     = "platform"
}

# ── Environment-specific config ───────────────────────────────────────────────
# These are overridden per workspace using local values below.
# You don't pass these in — terraform.workspace drives them automatically.

variable "eks_config" {
  description = "EKS cluster configuration per environment"
  type = map(object({
    cluster_version    = string
    node_instance_type = string
    node_min_size      = number
    node_max_size      = number
    node_desired_size  = number
  }))
  default = {
    dev = {
      cluster_version    = "1.32"
      node_instance_type = "c7i-flex.large"  # cheap for dev
      node_min_size      = 1
      node_max_size      = 2
      node_desired_size  = 1
    }
    prod = {
      cluster_version    = "1.32"
      node_instance_type = "c7i-flex.large"   # more headroom for prod
      node_min_size      = 2
      node_max_size      = 5
      node_desired_size  = 3            # matches replicaCount: 3 in prod helm values
    }
  }
}

variable "services" {
  description = "List of microservices — one ECR repository is created per service"
  type        = list(string)
  default     = ["api-gateway", "user-service", "order-service"]
}
