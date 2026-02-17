variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "validator_name" {
  description = "Name of the validator"
  type        = string
  default     = "validator-01"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "enable_dns" {
  description = "Enable DNS configuration"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "DNS zone name"
  type        = string
  default     = ""
}

variable "node_instance_types" {
  description = "EC2 instance types for nodes"
  type        = list(string)
  default     = ["r6a.xlarge", "r6i.xlarge", "m6a.2xlarge"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 4
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "movement-l1"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}