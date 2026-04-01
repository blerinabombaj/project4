variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "service_name" {
  description = "Name of the microservice (e.g. api-gateway)"
  type        = string
}

variable "eks_node_role_arn" {
  description = "IAM role ARN of EKS node group — granted pull access to this repo"
  type        = string
}
