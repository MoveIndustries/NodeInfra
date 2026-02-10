locals {
  labels = {
    app                             = var.node_id
    "movementnetwork.xyz/node"      = var.node_id
    "movementnetwork.xyz/node_type" = "pfn"
    "movementnetwork.xyz/network"   = var.network_name
    "movementnetwork.xyz/chain_id"  = var.chain_id
  }

  config_path = "${path.module}/configs/${var.network_name}.${var.node_name}.yaml"
}

resource "kubernetes_config_map" "node_config" {
  metadata {
    namespace = var.namespace
    name      = "${var.node_id}-config"
    labels    = local.labels
  }

  data = {
    "fullnode.yaml" = file(local.config_path)
  }
}

resource "kubernetes_persistent_volume_claim" "node_storage" {
  metadata {
    namespace = var.namespace
    name      = "${var.node_id}-data"
    labels    = local.labels
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = var.storage_size
      }
    }

    storage_class_name = var.storage_class != "" ? var.storage_class : null
  }

  wait_until_bound = false
}

resource "kubernetes_stateful_set" "fullnode" {
  wait_for_rollout = false

  metadata {
    namespace = var.namespace
    name      = var.node_id
    labels    = local.labels
  }

  spec {
    service_name = var.node_id
    replicas     = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          "prometheus.io/scrape" = var.enable_metrics ? "true" : "false"
          "prometheus.io/port"   = tostring(var.metrics_port)
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 6180
          run_as_group    = 6180
          fs_group        = 6180
        }

        init_container {
          name    = "genesis-setup"
          image   = "curlimages/curl:8.10.1"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOF
            set -ex
            mkdir -p /opt/data/genesis
            curl -o /opt/data/genesis/genesis.blob https://raw.githubusercontent.com/movementlabsxyz/movement-networks/main/${var.network_name}/genesis.blob
            curl -o /opt/data/genesis/genesis_waypoint.txt https://raw.githubusercontent.com/movementlabsxyz/movement-networks/main/${var.network_name}/genesis_waypoint.txt
            curl -o /opt/data/genesis/waypoint.txt https://raw.githubusercontent.com/movementlabsxyz/movement-networks/main/${var.network_name}/waypoint.txt
            EOF
          ]

          volume_mount {
            name       = "aptos-data"
            mount_path = "/opt/data"
          }
        }

        container {
          name  = "fullnode"
          image = "${var.image.repository}:${var.image.tag}"
          args  = ["--config", "/etc/aptos/fullnode.yaml"]

          port {
            name           = "api"
            container_port = var.api_port
            protocol       = "TCP"
          }

          port {
            name           = "p2p"
            container_port = var.p2p_port
            protocol       = "TCP"
          }

          dynamic "port" {
            for_each = var.enable_metrics ? [1] : []
            content {
              name           = "metrics"
              container_port = var.metrics_port
              protocol       = "TCP"
            }
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          volume_mount {
            name       = "aptos-data"
            mount_path = "/opt/data"
          }

          volume_mount {
            name       = "node-config"
            mount_path = "/etc/aptos"
            read_only  = true
          }
        }

        volume {
          name = "aptos-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.node_storage.metadata[0].name
          }
        }

        volume {
          name = "node-config"
          config_map {
            name = kubernetes_config_map.node_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "public_fullnode" {
  metadata {
    namespace   = var.namespace
    name        = var.node_id
    labels      = local.labels
    annotations = var.service_annotations
  }

  spec {
    type = "LoadBalancer"

    selector = local.labels

    port {
      name        = "api"
      port        = var.api_port
      target_port = var.api_port
      protocol    = "TCP"
    }

    port {
      name        = "p2p"
      port        = var.p2p_port
      target_port = var.p2p_port
      protocol    = "TCP"
    }

    dynamic "port" {
      for_each = var.enable_metrics ? [1] : []
      content {
        name        = "metrics"
        port        = var.metrics_port
        target_port = var.metrics_port
        protocol    = "TCP"
      }
    }

    session_affinity = "None"
  }
}
