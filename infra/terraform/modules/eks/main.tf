# modules/eks/main.tf
#
# Creates an EKS cluster with a managed node group.
# EKS = AWS's managed Kubernetes control plane. You don't manage etcd,
# the API server, or the scheduler — AWS does. You only manage nodes.

# ── IAM Role for EKS Control Plane ───────────────────────────────────────────
# The cluster itself needs a role to call AWS APIs (e.g. create load balancers,
# describe EC2 instances for node registration).
resource "aws_iam_role" "cluster" {
  name = "${var.project}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── IAM Role for Node Group ───────────────────────────────────────────────────
# EC2 nodes need permissions to join the cluster, pull ECR images,
# and publish logs/metrics to CloudWatch.
resource "aws_iam_role" "nodes" {
  name = "${var.project}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes_worker" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "nodes_cni" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"  # for pod networking
}

resource "aws_iam_role_policy_attachment" "nodes_ecr" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.environment}"
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true   # nodes communicate with control plane privately
    endpoint_public_access  = true   # you can still run kubectl from your machine
  }

  # Useful logs for debugging auth issues, API calls, and scheduler decisions
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ── Managed Node Group ────────────────────────────────────────────────────────
# Managed = AWS handles node OS patching and replacement.
# Nodes run in your VPC subnets and register themselves with the cluster.
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids

  instance_types = [var.node_instance_type]

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  # Rolling update — replace nodes one at a time during K8s version upgrades
  update_config {
    max_unavailable = 1
  }

  # Taint nodes during updates so no new pods are scheduled on nodes being replaced
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]  # allow cluster autoscaler to manage this
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_worker,
    aws_iam_role_policy_attachment.nodes_cni,
    aws_iam_role_policy_attachment.nodes_ecr,
  ]
}
