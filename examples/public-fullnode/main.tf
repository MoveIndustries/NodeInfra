# AWS Provider
provider "aws" {
  region = var.region
}

locals {
  fullnode_bootstrap_enabled       = var.fullnode_bootstrap_s3_bucket != ""
  fullnode_bootstrap_prefix        = trim(var.fullnode_bootstrap_s3_prefix, "/")
  fullnode_bootstrap_object_arn    = local.fullnode_bootstrap_prefix != "" ? "arn:aws:s3:::${var.fullnode_bootstrap_s3_bucket}/${local.fullnode_bootstrap_prefix}/*" : "arn:aws:s3:::${var.fullnode_bootstrap_s3_bucket}/*"
  fullnode_bootstrap_s3_uri        = local.fullnode_bootstrap_enabled ? "s3://${var.fullnode_bootstrap_s3_bucket}${local.fullnode_bootstrap_prefix != "" ? "/${local.fullnode_bootstrap_prefix}" : ""}" : ""
  fullnode_bootstrap_region        = var.fullnode_bootstrap_s3_region != "" ? var.fullnode_bootstrap_s3_region : var.region
  fullnode_service_account_name    = var.fullnode_service_account_name != "" ? var.fullnode_service_account_name : (local.fullnode_bootstrap_enabled ? "${var.fullnode_id}-s3" : "")
  fullnode_service_account_enabled = local.fullnode_service_account_name != ""
}

# Network Infrastructure
module "network" {
  source = "../../terraform-modules/movement-network-base"

  validator_name = var.validator_name
  region         = var.region
  vpc_cidr       = var.vpc_cidr
  dns_enabled    = var.enable_dns
  dns_zone_name  = var.dns_zone_name

  # Cost optimization: single NAT gateway for demo
  single_nat_gateway = true

  tags = var.tags
}

# EKS Cluster Infrastructure
module "eks" {
  source = "../../terraform-modules/movement-validator-infra"

  cluster_name       = "${var.validator_name}-cluster"
  kubernetes_version = var.kubernetes_version

  vpc_id                          = module.network.vpc_id
  private_subnet_ids              = module.network.private_subnet_ids
  control_plane_security_group_id = module.network.control_plane_security_group_id
  node_security_group_id          = module.network.node_security_group_id

  node_instance_types = var.node_instance_types
  node_desired_size   = 1
  node_min_size       = 1
  node_max_size       = 2
  node_disk_size      = 100

  cluster_log_retention_days = 3

  enable_irsa = true

  tags = var.tags

  depends_on = [module.network]
}

# Optional: IRSA role + service account for S3 bootstrap
data "aws_iam_policy_document" "fullnode_s3_assume" {
  count = local.fullnode_bootstrap_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.fullnode_namespace}:${local.fullnode_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "fullnode_s3_read" {
  count = local.fullnode_bootstrap_enabled ? 1 : 0

  statement {
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.fullnode_bootstrap_s3_bucket}"]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = [local.fullnode_bootstrap_object_arn]
  }
}

resource "aws_iam_role" "fullnode_s3" {
  count = local.fullnode_bootstrap_enabled ? 1 : 0

  name               = "${var.validator_name}-fullnode-s3"
  assume_role_policy = data.aws_iam_policy_document.fullnode_s3_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "fullnode_s3_read" {
  count = local.fullnode_bootstrap_enabled ? 1 : 0

  role   = aws_iam_role.fullnode_s3[0].id
  policy = data.aws_iam_policy_document.fullnode_s3_read[0].json
}
