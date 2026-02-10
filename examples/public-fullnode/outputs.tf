output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "public_fullnode_hostname" {
  description = "Load balancer hostname for the public fullnode"
  value       = module.public_fullnode.load_balancer_hostname
}

output "public_fullnode_api_url" {
  description = "Public fullnode API URL"
  value       = "http://${module.public_fullnode.load_balancer_hostname}:${module.public_fullnode.api_port}/v1"
}

output "public_fullnode_api_port" {
  description = "Public fullnode API port"
  value       = module.public_fullnode.api_port
}

output "public_fullnode_namespace" {
  description = "Namespace for the public fullnode"
  value       = module.public_fullnode.namespace
}

output "public_fullnode_service_name" {
  description = "Service name for the public fullnode"
  value       = module.public_fullnode.service_name
}

output "public_fullnode_dns_name" {
  description = "DNS name for the public fullnode (if enabled)"
  value       = var.enable_dns && var.fullnode_dns_name != "" ? var.fullnode_dns_name : ""
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
