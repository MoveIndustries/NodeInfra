variable "validator_name" {
  description = "Unique name for this validator (e.g., alice, bob)"
  type        = string
  default     = "hello-world"
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
  default     = ["t3.xlarge"] # Smaller instance for hello-world
}

variable "enable_dns" {
  description = "Enable DNS record creation (requires existing Route53 zone)"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Route53 zone name (if enable_dns = true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "movement-validator"
    Environment = "demo"
    Purpose     = "hello-world"
  }
}
