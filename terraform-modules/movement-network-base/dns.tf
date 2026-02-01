# Data source for existing Route53 zone (if DNS is enabled)
data "aws_route53_zone" "main" {
  count = var.dns_enabled && var.dns_zone_name != "" ? 1 : 0

  name         = var.dns_zone_name
  private_zone = false
}
