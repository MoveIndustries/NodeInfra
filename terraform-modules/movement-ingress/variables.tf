variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL (for IRSA)"
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN (for IRSA)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS-01 challenge"
  type        = string
  default     = "Z01726943LS9E7WG35N3V" # scratchpad.movementnetwork.xyz
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name"
  type        = string
  default     = "scratchpad.movementnetwork.xyz"
}

variable "wildcard_domain" {
  description = "Wildcard domain for TLS certificate (e.g., *.{chain_name}.{ingress_domain})"
  type        = string
}

variable "ingress_namespace" {
  description = "Namespace for NGINX Ingress Controller"
  type        = string
  default     = "ingress-nginx"
}

variable "certmanager_namespace" {
  description = "Namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "node_namespace" {
  description = "Namespace where movement nodes are deployed (for TLS secret sync)"
  type        = string
  default     = "movement-l1"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
