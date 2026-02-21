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

  # Cost optimization: single NAT gateway for demo
  single_nat_gateway = true

  # Optional DNS configuration
  dns_enabled   = var.enable_dns
  dns_zone_name = var.dns_zone_name

  tags = var.tags
}

# EKS Cluster Infrastructure
module "eks" {
  source = "../../terraform-modules/movement-validator-infra"

  cluster_name       = "${var.validator_name}-cluster"
  kubernetes_version = var.kubernetes_version

  private_subnet_ids              = module.network.private_subnet_ids
  control_plane_security_group_id = module.network.control_plane_security_group_id

  # Node configuration (smaller for demo)
  node_instance_types = var.node_instance_types
  node_desired_size   = 1
  node_min_size       = 1
  node_max_size       = 2
  node_disk_size      = 50 # Smaller disk for demo

  # Reduce log retention for demo
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

# Demo Namespace
resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
    labels = {
      name    = "demo"
      purpose = "hello-world"
    }
  }

  depends_on = [module.eks]
}

# Hello World Deployment
resource "kubernetes_deployment" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.demo.metadata[0].name
    labels = {
      app = "hello-world"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "hello-world"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello-world"
        }
      }

      spec {
        container {
          name  = "hello-world"
          image = "hashicorp/http-echo:latest"

          args = [
            "-text=Hello World from Movement Validator Infrastructure! 🚀"
          ]

          port {
            name           = "http"
            container_port = 5678
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 5678
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 5678
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.demo]
}

# Hello World Service (LoadBalancer)
resource "kubernetes_service" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.demo.metadata[0].name
    labels = {
      app = "hello-world"
    }
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "hello-world"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 5678
      protocol    = "TCP"
    }

    session_affinity = "None"
  }

  depends_on = [kubernetes_deployment.hello_world]
}

# Data source to get the actual load balancer details
data "aws_lb" "hello_world" {
  count = var.enable_dns && var.dns_zone_name != "" ? 1 : 0

  tags = {
    "kubernetes.io/service-name" = "${kubernetes_namespace.demo.metadata[0].name}/${kubernetes_service.hello_world.metadata[0].name}"
  }

  depends_on = [kubernetes_service.hello_world]
}

# Optional: DNS Record
resource "aws_route53_record" "hello_world" {
  count = var.enable_dns && var.dns_zone_name != "" ? 1 : 0

  zone_id = module.network.dns_zone_id
  name    = module.network.validator_dns_name
  type    = "A"

  alias {
    name                   = data.aws_lb.hello_world[0].dns_name
    zone_id                = data.aws_lb.hello_world[0].zone_id
    evaluate_target_health = true
  }

  depends_on = [kubernetes_service.hello_world, data.aws_lb.hello_world]
}
