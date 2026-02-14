variable "validator_name" {
  description = "Unique name for this validator (used to name the cluster)"
  type        = string
  default     = "public-fullnode"
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "EC2 instance types for nodes"
  type        = list(string)
  default     = ["c6a.4xlarge"]
}

variable "fullnode_network_name" {
  description = "Network name used for fullnode config selection"
  type        = string
  default     = "testnet"
}

variable "fullnode_node_name" {
  description = "Fullnode config name (e.g., pfn-restore)"
  type        = string
  default     = "pfn-restore"
}

variable "fullnode_id" {
  description = "Fullnode resource name"
  type        = string
  default     = "public-fullnode"
}

variable "fullnode_namespace" {
  description = "Kubernetes namespace for the public fullnode deployment"
  type        = string
  default     = "movement-l1"
}

variable "fullnode_chain_id" {
  description = "Chain ID label for the fullnode"
  type        = string
  default     = ""
}

variable "fullnode_image" {
  description = "Fullnode image repository and tag"
  type = object({
    repository = string
    tag        = string
  })
  default = {
    repository = "ghcr.io/movementlabsxyz/aptos-node"
    tag        = "latest"
  }
}

variable "fullnode_storage_size" {
  description = "Fullnode persistent volume size"
  type        = string
  default     = "500Gi"
}

variable "fullnode_storage_class" {
  description = "Storage class for fullnode PVC (leave empty for default)"
  type        = string
  default     = ""
}

variable "fullnode_data_dir" {
  description = "Data directory for the fullnode inside the container"
  type        = string
  default     = "/opt/data/aptos"
}

variable "fullnode_bootstrap_s3_bucket" {
  description = "S3 bucket containing existing blockchain data to bootstrap from"
  type        = string
  default     = ""
}

variable "fullnode_bootstrap_s3_prefix" {
  description = "Optional prefix inside the S3 bucket for bootstrap data"
  type        = string
  default     = ""
}

variable "fullnode_bootstrap_s3_region" {
  description = "AWS region for the bootstrap S3 bucket (defaults to var.region when empty)"
  type        = string
  default     = ""
}

variable "fullnode_service_account_name" {
  description = "Service account name for the fullnode pod (IRSA/S3 access)"
  type        = string
  default     = ""
}

variable "fullnode_resources" {
  description = "Kubernetes resource allocations for the fullnode"
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

variable "fullnode_enable_metrics" {
  description = "Expose metrics port on the public fullnode service"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "movement-validator"
    Environment = "testnet"
    Purpose     = "public-fullnode"
  }
}

variable "enable_dns" {
  description = "Create a Route53 DNS record for the public fullnode"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Route53 zone name (if enable_dns = true)"
  type        = string
  default     = ""
}

variable "fullnode_dns_name" {
  description = "Full DNS name for the public fullnode (if enable_dns = true)"
  type        = string
  default     = ""
}
