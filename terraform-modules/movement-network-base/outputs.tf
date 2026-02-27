output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancers"
  value       = aws_subnet.public[*].id
}

output "availability_zones" {
  description = "Availability zones used"
  value       = local.azs
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = var.enable_nat_gateway ? aws_nat_gateway.main[*].id : []
}

output "control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  value       = aws_security_group.control_plane.id
}

output "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.node.id
}

output "load_balancer_security_group_id" {
  description = "Security group ID for load balancers"
  value       = aws_security_group.load_balancer.id
}

output "dns_zone_id" {
  description = "Route53 zone ID (empty if DNS not enabled)"
  value       = try(data.aws_route53_zone.main[0].zone_id, "")
}

output "dns_zone_name" {
  description = "Route53 zone name"
  value       = var.dns_zone_name
}

output "validator_dns_name" {
  description = "Full DNS name for validator endpoint"
  value       = var.dns_enabled && var.dns_zone_name != "" ? "${var.validator_name}.${var.region}.${var.dns_zone_name}" : ""
}
