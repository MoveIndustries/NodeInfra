# Movement Network Validator Infrastructure

Native Terraform HCL infrastructure for deploying Movement Network validators with complete isolation, modularity, and reusability.

## Project Status

| Milestone | Status | Progress |
|-----------|--------|----------|
| **M1: Foundation & Hello World** | ✅ Complete | 100% |
| **M2: Validator Node** | ⬜ Not Started | 0% |
| **M3: VFN + Full Node** | ⬜ Not Started | 0% |
| **M4: Observability Cluster** | ⬜ Not Started | 0% |

**Current Phase:** Milestone 1 Complete - Ready for Milestone 2

## Overview

This project provides production-ready Terraform modules and Helm charts for deploying Movement Network validators on AWS EKS. The infrastructure follows a modular, one-VPC-per-validator design that enables complete isolation and independent scaling.

### Key Features

- ✅ **Native Terraform HCL** - No CDKTF complexity
- ✅ **One VPC Per Validator** - Complete network isolation
- ✅ **Modular Design** - Reusable infrastructure components
- ✅ **Public Modules** - External organizations can deploy validators
- ✅ **Security First** - AWS Secrets Manager, IRSA, encrypted volumes
- ✅ **Cost Optimized** - Configurable for production or development
- ✅ **Well Documented** - Comprehensive guides and examples

## Quick Start

### Deploy Hello World Example

```bash
# Navigate to hello-world example
cd examples/hello-world

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
terraform init
terraform apply

# Test
curl $(terraform output -raw hello_world_url)
# Expected: Hello World from Movement Validator Infrastructure! 🚀

# Cleanup
terraform destroy
```

**Deployment time:** ~10-15 minutes | **Cost:** ~$0.34/hour

## Repository Structure

```
NodeInfra/
├── terraform-modules/           # Reusable Terraform modules
│   ├── movement-network-base/   # ✅ VPC, subnets, security groups
│   └── movement-validator-infra/# ✅ EKS cluster, nodes, IAM
│
├── examples/                    # Example deployments
│   └── hello-world/             # ✅ M1: Basic infrastructure demo
│
├── tests/                       # Integration tests
│   └── integration/
│       └── test-hello-world.sh  # ✅ M1 test suite
│
└── docs/
    ├── MILESTONE_PLAN.md        # Detailed 4-milestone roadmap
    ├── M1_PROGRESS.md           # ✅ M1 completion report
    └── validator-infrastructure-redesign-v2.md
```

## Modules

### movement-network-base ✅

Network infrastructure with VPC, subnets, NAT gateways, and security groups.

**Key Features:**
- VPC with configurable CIDR (reusable across validators)
- Multi-AZ: 2 public + 2 private subnets
- HA NAT gateways or single NAT for cost savings
- Pre-configured security groups for EKS
- Optional Route53 DNS integration

[Documentation →](terraform-modules/movement-network-base/README.md)

### movement-validator-infra ✅

EKS infrastructure with Kubernetes cluster, managed nodes, and IAM.

**Key Features:**
- EKS 1.35 with encrypted secrets
- Auto-scaling managed node groups
- IRSA for pod-level IAM permissions
- EBS CSI driver pre-installed
- CloudWatch logging enabled

[Documentation →](terraform-modules/movement-validator-infra/README.md)

## Milestones

### ✅ Milestone 1: Foundation & Hello World

**Status:** Complete
**Duration:** ~4 hours

**Deliverables:**
- ✅ movement-network-base module
- ✅ movement-validator-infra module
- ✅ hello-world example
- ✅ Integration tests
- ✅ Documentation

[M1 Progress Report →](M1_PROGRESS.md)

### ⬜ Milestone 2: Validator Node (Next)

**Goals:**
- AWS Secrets Manager integration
- External Secrets Operator
- movement-validator Helm chart
- Deploy Aptos validator
- Validate block production

**Duration:** 2-3 weeks

### ⬜ Milestone 3: VFN + Full Node

**Goals:**
- movement-vfn Helm chart
- movement-fullnode Helm chart
- Complete network topology
- Load balancer + DNS
- Public API access

**Duration:** 2-3 weeks

### ⬜ Milestone 4: Observability Cluster

**Goals:**
- Separate observability cluster
- VictoriaMetrics + Loki + Grafana
- Push-based metrics/logs
- Pre-built dashboards

**Duration:** 2 weeks

[Full Milestone Plan →](MILESTONE_PLAN.md)

## Cost Estimates

### Hello World Demo
~$245/month if left running (~$0.34/hour)

### Production Validator
~$703/month per validator

**Cost Optimization:**
- Use spot instances (70% savings)
- Single NAT gateway for dev/test
- Destroy resources when not in use

## Development

### Linting

This repository uses comprehensive linting to ensure code quality and consistency:

**Quick Start:**
```bash
# Run all linting checks
make lint

# Format all Terraform files
make fmt

# Run specific checks
make fmt-check    # Check formatting only
make tflint       # Run TFLint only
make validate     # Run terraform validate only
```

**Available Linting Tools:**
- **terraform fmt** - Canonical Terraform formatting
- **TFLint** - Advanced linting with AWS best practices
- **terraform validate** - Syntax and configuration validation

**First Time Setup:**
```bash
# Install required tools (macOS/Linux)
make install-tools

# Or install manually
brew install tflint terraform-docs
```

**CI/CD:**
All pull requests automatically run linting checks via GitHub Actions.

### Testing

Run integration tests:

```bash
cd tests/integration
./test-hello-world.sh
```

Validates:
- Infrastructure deployment
- HTTP endpoint functionality
- Kubernetes resource health
- Automatic cleanup

## Documentation

- [Design Document](validator-infrastructure-redesign-v2.md) - Architecture rationale
- [Milestone Plan](MILESTONE_PLAN.md) - Implementation roadmap
- [M1 Progress](M1_PROGRESS.md) - Milestone 1 summary
- [Network Module](terraform-modules/movement-network-base/README.md)
- [EKS Module](terraform-modules/movement-validator-infra/README.md)
- [Hello World](examples/hello-world/README.md)

## Key Design Principles

1. **One VPC Per Validator** - Complete network isolation
2. **Modularity** - Reusable, composable components
3. **Security by Default** - Encryption, IRSA, least privilege
4. **Simplicity** - Native Terraform, no unnecessary abstraction
5. **External Adoption** - Public modules for any organization

---

**Status:** Milestone 1 Complete ✅ | **Next:** M2 - Validator Node | **Updated:** 2026-01-30