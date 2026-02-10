# Movement Network Base Module

This Terraform module creates the foundational networking infrastructure for a Movement validator, including VPC, subnets, NAT gateways, security groups, and optional DNS configuration.

## Features

- **VPC with Configurable CIDR**: Default 10.0.0.0/20 (can be reused across validators)
- **Multi-AZ Setup**: 2 public and 2 private subnets across 2 availability zones
- **High Availability**: NAT gateways in each AZ (or single NAT for cost savings)
- **Security Groups**: Pre-configured for EKS control plane, nodes, and load balancers
- **DNS Support**: Optional Route53 integration
- **Kubernetes Ready**: Subnet tags for automatic ELB discovery

## Architecture

```
VPC (10.0.0.0/20)
├── Public Subnets (2 AZs)
│   ├── 10.0.0.0/24 (AZ-1)
│   └── 10.0.1.0/24 (AZ-2)
├── Private Subnets (2 AZs)
│   ├── 10.0.2.0/24 (AZ-1)
│   └── 10.0.3.0/24 (AZ-2)
├── Internet Gateway
├── NAT Gateways (2)
└── Security Groups
    ├── EKS Control Plane
    ├── EKS Nodes
    └── Load Balancers
```

## Usage

```hcl
module "network" {
  source = "../../terraform-modules/movement-network-base"

  validator_name = "alice"
  region         = "us-east-1"
  vpc_cidr       = "10.0.0.0/20"

  # Optional: Enable DNS
  dns_enabled   = true
  dns_zone_name = "movementnetwork.xyz"

  # Optional: Use single NAT gateway for cost savings
  single_nat_gateway = false

  tags = {
    Environment = "production"
    Project     = "movement-validator"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| validator_name | Unique name for validator | string | - | yes |
| region | AWS region | string | "us-east-1" | no |
| vpc_cidr | VPC CIDR block | string | "10.0.0.0/20" | no |
| availability_zones | List of AZs (auto-detected if empty) | list(string) | [] | no |
| enable_nat_gateway | Enable NAT gateway | bool | true | no |
| single_nat_gateway | Use single NAT (cost savings) | bool | false | no |
| dns_enabled | Enable DNS records | bool | false | no |
| dns_zone_name | Route53 zone name | string | "" | no |
| tags | Common resource tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | VPC ID |
| vpc_cidr | VPC CIDR block |
| private_subnet_ids | Private subnet IDs for EKS |
| public_subnet_ids | Public subnet IDs for load balancers |
| control_plane_security_group_id | EKS control plane security group |
| node_security_group_id | EKS node security group |
| load_balancer_security_group_id | Load balancer security group |
| dns_zone_id | Route53 zone ID |
| validator_dns_name | Full DNS name for validator |

## Network Isolation

Each validator deployment gets its own VPC, providing complete network isolation:

- **Private IPs can overlap** across validators (e.g., all can use 10.0.0.0/20)
- No VPC peering required between validators
- Each validator has independent routing and security
- Network failures are isolated to single validator

## Cost Considerations

### NAT Gateway Costs
- **High Availability** (2 NAT gateways): ~$64/month
- **Cost Optimized** (1 NAT gateway): ~$32/month

Set `single_nat_gateway = true` for development/testing environments.

### Total Networking Costs
- VPC: Free
- Subnets: Free
- Internet Gateway: Free
- NAT Gateway: $32-64/month
- Data transfer: Variable

## Security

### Security Groups

**Control Plane SG:**
- Ingress: 443 from node SG
- Egress: All traffic

**Node SG:**
- Ingress: All from self, 1025-65535 from control plane
- Egress: All traffic

**Load Balancer SG:**
- Ingress: 80, 443, 6182 from anywhere
- Egress: All traffic

## Examples

See `examples/hello-world/` for a complete deployment example.

## Requirements

- Terraform >= 1.9.0
- AWS Provider ~> 5.0

## Notes

- VPC CIDR can be reused across different validators since they're isolated
- DNS zone must exist before enabling DNS (module does not create zones)
- Subnet CIDR blocks are automatically calculated from VPC CIDR
