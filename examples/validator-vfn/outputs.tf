output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "namespace" {
  description = "Kubernetes namespace for validator nodes"
  value       = var.namespace
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_id}"
}

# Ingress outputs (when enabled)
output "ingress_enabled" {
  description = "Whether ingress is enabled"
  value       = var.enable_ingress
}

output "ingress_base_domain" {
  description = "Base domain for ingress (Route53 zone, not including chain_name prefix)"
  value       = var.enable_ingress ? var.ingress_domain : ""
}

output "ingress_namespace" {
  description = "NGINX Ingress Controller namespace"
  value       = var.enable_ingress ? module.ingress[0].ingress_namespace : ""
}
