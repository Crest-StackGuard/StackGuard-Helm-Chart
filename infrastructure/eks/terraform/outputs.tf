output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "aws_account_id" {
  description = "AWS account ID (also readable by pods via IMDS when hop limit is 2)."
  value       = data.aws_caller_identity.current.account_id
}

output "imds_hop_limit" {
  description = "EC2 IMDS hop limit on nodes (must be >= 2 for in-pod cloud detection)."
  value       = 2
}

output "node_ami_id" {
  description = "Ubuntu EKS AMI ID used by the node group."
  value       = local.node_ami_id
}
