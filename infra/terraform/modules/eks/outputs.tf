output "cluster_name" {
  description = "EKS cluster name — used to configure kubectl"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint — used by Helm and kubectl"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA cert — used to verify the API server"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "node_role_arn" {
  description = "IAM role ARN of node group — passed to ECR module for pull permissions"
  value       = aws_iam_role.nodes.arn
}
