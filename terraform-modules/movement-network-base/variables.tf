variable "validator_name" {
  description = "Unique name for this validator (e.g., alice, bob)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.validator_name))
    error_message = "Validator name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (can reuse same CIDR across validators)"
  type        = string
  default     = "10.0.0.0/20"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones (defaults to first 2 in region)"
  type        = list(string)
  default     = []
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for cost savings (not recommended for production)"
  type        = bool
  default     = false
}

variable "dns_enabled" {
  description = "Enable DNS record creation"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "DNS zone name (e.g., movementnetwork.xyz)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
