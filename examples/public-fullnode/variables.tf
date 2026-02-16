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

variable "fullnode_id" {
  description = "Recommended Helm release/fullnode resource name"
  type        = string
  default     = "public-fullnode"
}

variable "fullnode_namespace" {
  description = "Kubernetes namespace used by the Helm release"
  type        = string
  default     = "movement-l1"
}

variable "fullnode_bootstrap_s3_bucket" {
  description = "S3 bucket containing blockchain data used by workload bootstrap init container"
  type        = string
  default     = ""
}

variable "fullnode_bootstrap_s3_prefix" {
  description = "Optional prefix inside the S3 bucket for bootstrap data"
  type        = string
  default     = ""
}

variable "fullnode_bootstrap_s3_region" {
  description = "AWS region for bootstrap S3 bucket (defaults to var.region when empty)"
  type        = string
  default     = ""
}

variable "fullnode_service_account_name" {
  description = "Kubernetes ServiceAccount name used by Helm workload for IRSA"
  type        = string
  default     = ""
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
