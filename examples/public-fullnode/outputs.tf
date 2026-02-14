output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "public_fullnode_api_port" {
  description = "Public fullnode API port"
  value       = 8080
}

output "public_fullnode_namespace" {
  description = "Namespace for the public fullnode"
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
  description = "Helm release name for the public fullnode"
  value       = var.fullnode_id
}

output "public_fullnode_helm_values" {
  description = "Helm values for the public fullnode release"
  value       = yamlencode(local.fullnode_helm_values)
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
