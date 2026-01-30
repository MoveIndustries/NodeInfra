output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "load_balancer_hostname" {
  description = "Load balancer hostname for hello-world service"
  value       = try(kubernetes_service.hello_world.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

output "hello_world_url" {
  description = "URL to access hello-world service"
  value       = "http://${try(kubernetes_service.hello_world.status[0].load_balancer[0].ingress[0].hostname, "pending")}"
}

output "dns_name" {
  description = "DNS name for hello-world (if DNS enabled)"
  value       = var.enable_dns ? module.network.validator_dns_name : ""
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
