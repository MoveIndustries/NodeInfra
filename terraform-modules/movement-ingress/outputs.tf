output "ingress_namespace" {
  description = "Namespace where NGINX Ingress Controller is deployed"
  value       = var.ingress_namespace
}

output "cert_manager_namespace" {
  description = "Namespace where cert-manager is deployed"
  value       = var.certmanager_namespace
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager"
  value       = aws_iam_role.cert_manager.arn
}

output "wildcard_certificate_secret" {
  description = "Name of the Kubernetes secret containing the wildcard TLS certificate"
  value       = "wildcard-tls"
}

output "cluster_issuer_name" {
  description = "Name of the ClusterIssuer for Let's Encrypt"
  value       = "letsencrypt-prod"
}

output "ingress_class_name" {
  description = "Ingress class name to use in Ingress resources"
  value       = "nginx"
}

output "load_balancer_hostname" {
  description = "NLB hostname for the NGINX Ingress Controller"
  value       = data.aws_lb.nginx_ingress.dns_name
}

output "wildcard_dns_record" {
  description = "DNS record name for the wildcard domain"
  value       = aws_route53_record.wildcard.name
}
