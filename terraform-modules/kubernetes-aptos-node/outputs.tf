output "service_name" {
  description = "Name of the public fullnode service"
  value       = kubernetes_service.public_fullnode.metadata[0].name
}

output "stateful_set_name" {
  description = "Name of the fullnode stateful set"
  value       = kubernetes_stateful_set.fullnode.metadata[0].name
}

output "persistent_volume_claim_name" {
  description = "Name of the persistent volume claim"
  value       = kubernetes_persistent_volume_claim.node_storage.metadata[0].name
}

output "load_balancer_hostname" {
  description = "Load balancer hostname for the public fullnode"
  value = coalesce(
    try(kubernetes_service.public_fullnode.status[0].load_balancer[0].ingress[0].hostname, ""),
    try(kubernetes_service.public_fullnode.status[0].load_balancer[0].ingress[0].ip, ""),
    "pending"
  )
}

output "api_port" {
  description = "API port for the public fullnode"
  value       = var.api_port
}

output "namespace" {
  description = "Namespace where the fullnode is deployed"
  value       = var.namespace
}
