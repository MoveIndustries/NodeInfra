# Movement Validator Infrastructure Module

This Terraform module creates the EKS infrastructure for running Movement validators, including the Kubernetes cluster, managed node groups, storage configuration, and IAM roles with IRSA support.

## Features

- **EKS Cluster**: Kubernetes 1.35 with encrypted secrets
- **Managed Node Group**: Auto-scaling with desired/min/max configuration
- **High-Performance Storage**: gp3 EBS volumes with optimized IOPS
- **IRSA Support**: IAM Roles for Service Accounts for pod-level permissions
- **EBS CSI Driver**: Pre-installed for dynamic volume provisioning
- **CloudWatch Logging**: Full control plane logging
- **Security**: Encrypted EBS volumes, IMDSv2, private endpoints

## Architecture

```
EKS Cluster
├── Control Plane (Managed by AWS)
│   ├── API Server
│   ├── etcd
│   └── Controller Manager
├── Managed Node Group
│   ├── Launch Template
│   │   ├── gp3 EBS (100GB, 3000 IOPS)
│   │   ├── IMDSv2 required
│   │   └── Monitoring enabled
│   └── Auto Scaling (1-3 nodes)
├── Add-ons
│   ├── VPC-CNI
│   ├── kube-proxy
│   ├── CoreDNS
│   └── EBS CSI Driver
└── IAM
    ├── Cluster Role
    ├── Node Role
    ├── OIDC Provider (IRSA)
    └── EBS CSI Driver Role
```

## Usage

```hcl
module "eks" {
  source = "../../terraform-modules/movement-validator-infra"

  cluster_name         = "alice-cluster"
  kubernetes_version   = "1.35"

  # From network-base module
  vpc_id                            = module.network.vpc_id
  private_subnet_ids                = module.network.private_subnet_ids
  control_plane_security_group_id   = module.network.control_plane_security_group_id
  node_security_group_id            = module.network.node_security_group_id

  # Node configuration
  node_instance_types = ["c6a.4xlarge"]
  node_desired_size   = 1
  node_min_size       = 1
  node_max_size       = 3
  node_disk_size      = 100

  # Enable IRSA for pod-level IAM permissions
  enable_irsa = true

  tags = {
    Environment = "production"
    Validator   = "alice"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | EKS cluster name | string | - | yes |
| kubernetes_version | Kubernetes version | string | "1.35" | no |
| vpc_id | VPC ID | string | - | yes |
| private_subnet_ids | Private subnet IDs for nodes | list(string) | - | yes |
| control_plane_subnet_ids | Subnets for control plane | list(string) | [] | no |
| control_plane_security_group_id | Control plane security group | string | "" | no |
| node_security_group_id | Node security group | string | "" | no |
| node_instance_types | EC2 instance types | list(string) | ["c6a.4xlarge"] | no |
| node_desired_size | Desired node count | number | 1 | no |
| node_min_size | Minimum node count | number | 1 | no |
| node_max_size | Maximum node count | number | 3 | no |
| node_disk_size | Node root disk size (GB) | number | 100 | no |
| enable_cluster_encryption | Enable secret encryption | bool | true | no |
| cluster_log_types | Control plane log types | list(string) | ["api", "audit", ...] | no |
| cluster_log_retention_days | Log retention days | number | 7 | no |
| enable_irsa | Enable IRSA | bool | true | no |
| tags | Resource tags | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | EKS cluster ID |
| cluster_name | EKS cluster name |
| cluster_endpoint | EKS API endpoint |
| cluster_ca_certificate | Cluster CA certificate (sensitive) |
| oidc_provider_arn | OIDC provider ARN for IRSA |
| oidc_provider_url | OIDC provider URL |
| node_role_arn | Node IAM role ARN |
| ebs_csi_driver_role_arn | EBS CSI driver role ARN |

## Node Configuration

### Instance Types

**Default: c6a.4xlarge**
- vCPUs: 16
- Memory: 32 GB
- Network: Up to 12.5 Gbps
- EBS Bandwidth: Up to 10 Gbps

Suitable for validator workloads requiring high CPU and network performance.

### Auto Scaling

Nodes automatically scale between min and max based on resource requests:
- **desired_size**: Starting number of nodes
- **min_size**: Minimum nodes (prevents scaling to zero)
- **max_size**: Maximum nodes (cost ceiling)

### Storage

- **Root Volume**: gp3, 100GB, 3000 IOPS, 125 MB/s throughput
- **Encrypted**: All EBS volumes encrypted at rest
- **Dynamic Provisioning**: EBS CSI driver for PVC support

## Security Features

### IMDSv2 Required
All nodes require IMDSv2 for instance metadata access, preventing SSRF attacks.

### Encrypted Secrets
Kubernetes secrets encrypted at rest using AWS KMS.

### Private Endpoints
Control plane accessible from VPC (public endpoint can be disabled).

### IAM Roles for Service Accounts (IRSA)
Pods can assume IAM roles without node-level permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/my-pod-role
```

## EKS Add-ons

### VPC-CNI
Kubernetes networking plugin for AWS VPC integration.

### CoreDNS
Cluster DNS service for service discovery.

### kube-proxy
Network proxy for Kubernetes services.

### EBS CSI Driver
Dynamic provisioning of EBS volumes for persistent storage.

## Cost Considerations

### EKS Control Plane
- **Cost**: ~$73/month per cluster
- **Included**: Highly available control plane across 3 AZs

### EC2 Nodes (c6a.4xlarge)
- **On-Demand**: ~$0.688/hour (~$500/month per node)
- **Spot**: ~$0.206/hour (~$150/month per node, 70% savings)

### EBS Volumes
- **Root (100GB gp3)**: ~$8/month per node
- **Validator Storage (500GB gp3, 6000 IOPS)**: ~$50/month

### CloudWatch Logs
- **7-day retention**: ~$1-5/month depending on verbosity

## Examples

See `examples/hello-world/` for a complete deployment example.

## Requirements

- Terraform >= 1.9.0
- AWS Provider ~> 5.0
- TLS Provider ~> 4.0

## Notes

- Control plane logging increases CloudWatch costs slightly
- Node group uses ignore_changes for desired_size to prevent drift
- EBS CSI driver requires IRSA for proper IAM permissions
- Nodes automatically join the cluster via EKS-managed bootstrap
