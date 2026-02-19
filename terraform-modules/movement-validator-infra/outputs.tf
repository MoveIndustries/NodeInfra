output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "EKS cluster platform version"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : ""
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  value       = var.enable_irsa ? replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "") : ""
}

output "node_role_arn" {
  description = "IAM role ARN for EKS nodes"
  value       = aws_iam_role.node.arn
}

# Validator Identity Secret Outputs
output "validator_identity_secret_data" {
  description = "Validator identity secret data from AWS Secrets Manager (sensitive)"
  value       = var.validator_keys_secret_name != "" ? data.aws_secretsmanager_secret_version.validator_identity[0].secret_string : ""
  sensitive   = true
}

output "validator_identity_configured" {
  description = "Whether validator identity secret is configured"
  value       = var.validator_keys_secret_name != ""
}

output "node_role_name" {
  description = "IAM role name for nodes"
  value       = aws_iam_role.node.name
}

output "node_instance_profile_arn" {
  description = "IAM instance profile ARN for nodes"
  value       = aws_iam_instance_profile.node.arn
}

output "node_security_group_id" {
  description = "Security group ID for nodes"
  value       = aws_eks_node_group.main.resources[0].remote_access_security_group_id
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "cluster_log_group_name" {
  description = "CloudWatch log group name for cluster"
  value       = aws_cloudwatch_log_group.cluster.name
}
