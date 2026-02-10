# Data sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Local variables
locals {
  cluster_name = var.cluster_name

  control_plane_subnet_ids = length(var.control_plane_subnet_ids) > 0 ? var.control_plane_subnet_ids : var.private_subnet_ids

  common_tags = merge(
    var.tags,
    {
      "Cluster"   = var.cluster_name
      "ManagedBy" = "Terraform"
      "Module"    = "movement-validator-infra"
    }
  )
}
