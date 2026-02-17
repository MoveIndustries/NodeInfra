variable "cluster_name" {
  description = "EKS cluster name"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters and hyphens."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC ID from network-base module"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for node group"
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Subnet IDs for EKS control plane (defaults to private_subnet_ids)"
  type        = list(string)
  default     = []
}

variable "control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  type        = string
  default     = ""
}

variable "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  type        = string
  default     = ""
}

variable "node_instance_types" {
  description = "EC2 instance types for nodes"
  type        = list(string)
  default     = ["r6a.xlarge", "r6i.xlarge", "m6a.2xlarge"]  # Memory-optimized: 4 vCPU/32GB or 8 vCPU/32GB
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Node root disk size in GB"
  type        = number
  default     = 100
}

variable "enable_cluster_encryption" {
  description = "Enable EKS cluster secret encryption"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "EKS control plane logging types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
