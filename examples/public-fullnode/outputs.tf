output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "public_fullnode_namespace" {
  description = "Namespace for the public fullnode Helm release"
  value       = var.fullnode_namespace
}

output "public_fullnode_service_name" {
  description = "Service name for the public fullnode"
  value       = var.fullnode_id
}

output "public_fullnode_dns_name" {
  description = "DNS name for the public fullnode (if enabled)"
  value       = var.enable_dns && var.fullnode_dns_name != "" ? var.fullnode_dns_name : ""
}

output "public_fullnode_release_name" {
  description = "Recommended Helm release name for the public fullnode"
  value       = var.fullnode_id
}

output "region" {
  description = "AWS region where infra was provisioned"
  value       = var.region
}

output "fullnode_bootstrap_enabled" {
  description = "Whether S3 bootstrap support was provisioned"
  value       = local.fullnode_bootstrap_enabled
}

output "fullnode_bootstrap_s3_uri" {
  description = "S3 URI workload should use for bootstrap (if enabled)"
  value       = local.fullnode_bootstrap_s3_uri
}

output "fullnode_bootstrap_region" {
  description = "S3 region workload should use for bootstrap (if enabled)"
  value       = local.fullnode_bootstrap_region
}

output "fullnode_service_account_name" {
  description = "ServiceAccount name workload should use for IRSA (if set)"
  value       = local.fullnode_service_account_name
}

output "fullnode_s3_role_arn" {
  description = "IAM role ARN workload should annotate on ServiceAccount (if enabled)"
  value       = local.fullnode_bootstrap_enabled ? aws_iam_role.fullnode_s3[0].arn : ""
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
