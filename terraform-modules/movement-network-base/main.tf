# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Local variables
locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = merge(
    var.tags,
    {
      "Validator"   = var.validator_name
      "ManagedBy"   = "Terraform"
      "Module"      = "movement-network-base"
      "Environment" = "production"
    }
  )
}
