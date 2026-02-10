variable "namespace" {
  description = "Kubernetes namespace for the node"
  type        = string
  default     = "movement-l1"
}

variable "network_name" {
  description = "Network name used to select the config file (e.g., devnet, testnet)"
  type        = string
  default     = "testnet"
}

variable "node_name" {
  description = "Node name used for config file selection (e.g., pfn-restore)"
  type        = string
  default     = "pfn-restore"
}

variable "node_id" {
  description = "Unique identifier for the node (used for k8s resource names)"
  type        = string
  default     = "public-fullnode"
}

variable "chain_id" {
  description = "Chain ID label for the node"
  type        = string
  default     = ""
}

variable "image" {
  description = "Docker image for the node"
  type = object({
    repository = string
    tag        = string
  })
  default = {
    repository = "ghcr.io/movementlabsxyz/aptos-node"
    tag        = "latest"
  }
}

variable "resources" {
  description = "Kubernetes resource allocations for the node"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "4"
      memory = "8Gi"
    }
    limits = {
      cpu    = "8"
      memory = "16Gi"
    }
  }
}

variable "storage_size" {
  description = "Size of the persistent volume for node data"
  type        = string
  default     = "500Gi"
}

variable "storage_class" {
  description = "Storage class for the persistent volume claim (leave empty for default)"
  type        = string
  default     = "gp3"
}

variable "api_port" {
  description = "API port for the fullnode"
  type        = number
  default     = 8080
}

variable "p2p_port" {
  description = "P2P port for the fullnode"
  type        = number
  default     = 6182
}

variable "metrics_port" {
  description = "Metrics port for the fullnode"
  type        = number
  default     = 9101
}

variable "enable_metrics" {
  description = "Expose metrics port on the service"
  type        = bool
  default     = true
}

variable "service_annotations" {
  description = "Annotations to apply to the Kubernetes Service"
  type        = map(string)
  default = {
    "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
  }
}
