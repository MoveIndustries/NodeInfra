provider "aws" {
  region  = var.region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = merge(var.tags, {
      Validator = var.validator_name
    })
  }
}

# Network infrastructure
module "network" {
  source = "../../terraform-modules/movement-network-base"

  validator_name = var.validator_name
  region         = var.region
  vpc_cidr       = var.vpc_cidr
  dns_enabled    = var.enable_dns || var.enable_ingress
  dns_zone_name  = var.enable_ingress ? var.ingress_domain : (var.enable_dns ? var.dns_zone_name : "")

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

# Configure Helm provider
provider "helm" {
  kubernetes {
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
}

# Configure kubectl provider
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  load_config_file       = false

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

# Ingress infrastructure (NGINX Ingress Controller + cert-manager + wildcard TLS)
module "ingress" {
  source = "../../terraform-modules/movement-ingress"
  count  = var.enable_ingress ? 1 : 0

  cluster_name              = module.eks.cluster_name
  cluster_oidc_issuer_url   = "https://${module.eks.oidc_provider_url}"
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  route53_zone_id           = module.network.dns_zone_id
  route53_zone_name         = var.ingress_domain
  wildcard_domain           = "*.${var.chain_name}.${var.ingress_domain}"
  node_namespace            = var.namespace

  tags = var.tags

  depends_on = [module.eks, kubernetes_namespace.movement]
}
