# outputs.tf
#
# These values are used after `terraform apply` to configure kubectl,
# update Helm values files with real ECR URLs, and set up ArgoCD.

output "cluster_name" {
  description = "Run: aws eks update-kubeconfig --name <cluster_name> --region eu-west-1"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  description = "Map of service name → ECR URL. Use these in your Helm values-*.yaml files."
  value       = { for svc, mod in module.ecr : svc => mod.repository_url }
}
