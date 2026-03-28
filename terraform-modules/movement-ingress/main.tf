# Reflector for syncing TLS secrets across namespaces
resource "helm_release" "reflector" {
  name             = "reflector"
  repository       = "https://emberstack.github.io/helm-charts"
  chart            = "reflector"
  version          = "7.1.288"
  namespace        = "kube-system"
  create_namespace = false

  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }
}

# Generate a unique but predictable name for the NLB
locals {
  nlb_name = "${var.cluster_name}-ingress"
}

# NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3"
  namespace        = var.ingress_namespace
  create_namespace = true

  values = [
    yamlencode({
      controller = {
        replicaCount = 2
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            "service.beta.kubernetes.io/aws-load-balancer-name"            = local.nlb_name
          }
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        config = {
          "use-forwarded-headers"      = "true"
          "compute-full-forwarded-for" = "true"
        }
      }
    })
  ]
}

# cert-manager for automatic TLS certificate management
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.2"
  namespace        = var.certmanager_namespace
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cert_manager.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.cert_manager_route53
  ]
}

# ClusterIssuer for Let's Encrypt with Route53 DNS-01 challenge
resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "infrastructure@moveindustries.xyz"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region       = data.aws_region.current.name
                hostedZoneID = var.route53_zone_id
              }
            }
            selector = {
              dnsZones = [var.route53_zone_name]
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Wildcard Certificate
resource "kubectl_manifest" "wildcard_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-tls"
      namespace = var.ingress_namespace
    }
    spec = {
      secretName = "wildcard-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      commonName = var.wildcard_domain
      dnsNames = [
        var.wildcard_domain,
        trimsuffix(trimprefix(var.wildcard_domain, "*."), ".")
      ]
      secretTemplate = {
        annotations = {
          "reflector.v1.k8s.emberstack.com/reflection-allowed"            = "true"
          "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = var.node_namespace
          "reflector.v1.k8s.emberstack.com/reflection-auto-enabled"       = "true"
          "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces"    = var.node_namespace
        }
      }
    }
  })

  depends_on = [kubectl_manifest.cluster_issuer, helm_release.reflector]
}

data "aws_region" "current" {}

# NOTE: NLB provisioning is asynchronous. After helm_release.nginx_ingress completes,
# AWS needs 2-5 minutes to provision the actual NLB. If the first terraform apply fails
# with "no matching ELB found", wait a few minutes and rerun. This is expected behavior.
#
# The data source lookup will fail fast if NLB doesn't exist yet, which is preferable
# to blocking with arbitrary sleep times that may still be insufficient.

# Get the NLB by name (set via service annotation)
data "aws_lb" "nginx_ingress" {
  name = local.nlb_name

  depends_on = [helm_release.nginx_ingress]
}

# Create DNS record for the wildcard domain pointing to the NLB
# Using ALIAS record for better performance and native AWS integration
resource "aws_route53_record" "wildcard" {
  zone_id = var.route53_zone_id
  name    = var.wildcard_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.nginx_ingress.dns_name
    zone_id                = data.aws_lb.nginx_ingress.zone_id
    evaluate_target_health = true
  }
}
