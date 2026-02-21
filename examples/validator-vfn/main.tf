provider "aws" {
  region  = var.region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

# Network infrastructure
module "network" {
  source = "../../terraform-modules/movement-network-base"

  validator_name = var.validator_name
  region         = var.region
  vpc_cidr       = var.vpc_cidr
  dns_zone_name  = var.enable_dns ? var.dns_zone_name : ""

  tags = merge(
    var.tags,
    {
      Environment = "validator-vfn"
      ManagedBy   = "terraform"
    }
  )
}

# EKS cluster infrastructure
module "eks" {
  source = "../../terraform-modules/movement-validator-infra"

  cluster_name        = "${var.validator_name}-cluster"
  kubernetes_version  = var.kubernetes_version
  private_subnet_ids  = module.network.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  tags = var.tags

  depends_on = [module.network]
}

# Configure Kubernetes provider
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
      module.eks.cluster_id,
      "--region",
      var.region
    ]
  }
}

# Create namespace for validator nodes
resource "kubernetes_namespace" "movement" {
  metadata {
    name = var.namespace

    labels = {
      name = var.namespace
    }
  }
}
