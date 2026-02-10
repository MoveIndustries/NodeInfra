# AWS Provider
provider "aws" {
  region = var.region
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

# Configure Kubernetes Provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.region
    ]
  }
}

# Default StorageClass (gp3)
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type = "gp3"
  }

  depends_on = [module.eks]
}

# Namespace for public fullnode
resource "kubernetes_namespace" "movement_l1" {
  metadata {
    name = "movement-l1"
    labels = {
      name    = "movement-l1"
      purpose = "public-fullnode"
    }
  }

  depends_on = [module.eks]
}

# Public Fullnode Deployment
module "public_fullnode" {
  source = "../../terraform-modules/kubernetes-aptos-node"

  namespace    = kubernetes_namespace.movement_l1.metadata[0].name
  network_name = var.fullnode_network_name
  node_name    = var.fullnode_node_name
  node_id      = var.fullnode_id
  chain_id     = var.fullnode_chain_id

  image          = var.fullnode_image
  storage_size   = var.fullnode_storage_size
  storage_class  = var.fullnode_storage_class
  resources      = var.fullnode_resources
  enable_metrics = var.fullnode_enable_metrics

  depends_on = [kubernetes_namespace.movement_l1]
}

# Data source to get the actual load balancer details
data "aws_lb" "public_fullnode" {
  count = var.enable_dns && var.dns_zone_name != "" && var.fullnode_dns_name != "" ? 1 : 0

  tags = {
    "kubernetes.io/service-name" = "${kubernetes_namespace.movement_l1.metadata[0].name}/${module.public_fullnode.service_name}"
  }

  depends_on = [module.public_fullnode]
}

# Optional: DNS Record
resource "aws_route53_record" "public_fullnode" {
  count = var.enable_dns && var.dns_zone_name != "" && var.fullnode_dns_name != "" ? 1 : 0

  zone_id = module.network.dns_zone_id
  name    = var.fullnode_dns_name
  type    = "A"

  alias {
    name                   = data.aws_lb.public_fullnode[0].dns_name
    zone_id                = data.aws_lb.public_fullnode[0].zone_id
    evaluate_target_health = true
  }

  depends_on = [data.aws_lb.public_fullnode]
}
