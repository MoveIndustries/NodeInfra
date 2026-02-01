# Movement Network Infrastructure - Milestone Implementation Plan

**Version:** 1.0
**Date:** 2026-01-30
**Based on:** validator-infrastructure-redesign-v2.md
**Project:** Native Terraform HCL Validator Infrastructure

---

## Executive Summary

This document breaks down the infrastructure redesign into 4 comprehensive milestones, enabling incremental delivery, thorough testing, and early validation of core components. Each milestone delivers a working, deployable system that builds upon the previous milestone.

### Milestone Overview

| Milestone | Focus | Duration | Deliverable |
|-----------|-------|----------|-------------|
| **M1** | Foundation & Hello World | 2-3 weeks | Basic VPC + EKS + DNS + dummy pod |
| **M2** | Validator Node | 2-3 weeks | Working Aptos validator with secrets |
| **M3** | VFN + Full Node | 2-3 weeks | Complete validator cluster with VFN and optional fullnode |
| **M4** | Observability | 2 weeks | Push-based monitoring cluster |

---

## Milestone 1: Foundation & Hello World

**Goal:** Establish core infrastructure modules and validate deployment workflow with a simple "hello world" service.

### Objectives

- Create reusable Terraform modules for networking and EKS
- Validate VPC isolation model (one VPC per validator)
- Prove DNS integration works
- Establish CI/CD and testing patterns
- Deploy a simple workload to validate end-to-end flow

### Success Criteria

- [ ] `terraform apply` completes successfully in < 15 minutes
- [ ] HTTP request to DNS endpoint returns "Hello World"
- [ ] Infrastructure can be destroyed and recreated idempotently
- [ ] Terraform tests pass
- [ ] Documentation allows external user to deploy

---

### 1.1 Terraform Module: `movement-network-base`

**Purpose:** VPC, subnets, security groups, DNS

#### Files to Create

```
terraform-modules/movement-network-base/
├── main.tf              # Module entrypoint
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── vpc.tf               # VPC, subnets, NAT, IGW
├── security-groups.tf   # Security group rules
├── dns.tf               # Route53 or Cloudflare DNS
├── versions.tf          # Provider versions
└── README.md            # Module documentation
```

#### Key Resources

**VPC Configuration:**
- VPC with configurable CIDR (default: `10.0.0.0/20`)
- 2 public subnets (2 AZs)
- 2 private subnets (2 AZs)
- Internet Gateway
- 2 NAT Gateways (HA configuration)
- Route tables

**Security Groups:**
- EKS control plane security group
- Node security group (allow all from control plane)
- Load balancer security group (allow 80, 443, 6182 inbound)

**DNS (Optional):**
- Route53 hosted zone OR Cloudflare zone lookup
- A record placeholder for validator endpoint

#### Input Variables

```hcl
variable "validator_name" {
  description = "Unique name for this validator (e.g., alice, bob)"
  type        = string
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
}

variable "dns_provider" {
  description = "DNS provider: route53 or cloudflare"
  type        = string
  default     = "route53"
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
```

#### Outputs

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancers"
  value       = aws_subnet.public[*].id
}

output "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.node.id
}

output "dns_zone_id" {
  description = "DNS zone ID (Route53 or Cloudflare)"
  value       = var.dns_provider == "route53" ? aws_route53_zone.validator[0].id : data.cloudflare_zone.validator[0].id
}

output "validator_dns_name" {
  description = "DNS name for validator endpoint"
  value       = "${var.validator_name}.${var.region}.${var.dns_zone_name}"
}
```

#### Acceptance Tests

```hcl
# tests/network-base.tftest.hcl
run "validate_vpc_creation" {
  command = apply

  assert {
    condition     = length(aws_vpc.main.cidr_block) > 0
    error_message = "VPC CIDR must be set"
  }
}

run "validate_subnet_count" {
  command = apply

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Must have exactly 2 private subnets"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Must have exactly 2 public subnets"
  }
}
```

---

### 1.2 Terraform Module: `movement-validator-infra`

**Purpose:** EKS cluster, node groups, storage, IAM

#### Files to Create

```
terraform-modules/movement-validator-infra/
├── main.tf              # Module entrypoint
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── eks.tf               # EKS cluster
├── node-group.tf        # Self-managed node group
├── storage.tf           # EBS CSI driver, storage class
├── iam.tf               # IRSA roles
├── addons.tf            # EKS addons (VPC-CNI, kube-proxy)
├── versions.tf          # Provider versions
└── README.md            # Module documentation
```

#### Key Resources

**EKS Cluster:**
- EKS control plane (Kubernetes 1.35)
- Private endpoint access enabled
- Public endpoint access enabled (for CI/CD)
- CloudWatch logging for control plane

**Node Group:**
- Self-managed node group (Bottlerocket AMI)
- Instance type: `c6a.4xlarge` (16 vCPU, 32GB RAM)
- Min: 1, Desired: 1, Max: 3
- Spot instances optional (cost optimization)
- User data for Bottlerocket configuration

**Storage:**
- EBS CSI driver addon
- Storage class: `gp3-encrypted` with 6000 IOPS
- Volume snapshot class

**IAM:**
- EKS cluster role
- Node IAM role
- IRSA provider (OIDC)

#### Input Variables

```hcl
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
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

variable "node_instance_type" {
  description = "EC2 instance type for nodes"
  type        = string
  default     = "c6a.4xlarge"
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 1
}

variable "enable_spot_instances" {
  description = "Use spot instances for cost savings"
  type        = bool
  default     = false
}
```

#### Outputs

```hcl
output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_cert" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "node_role_arn" {
  description = "IAM role ARN for nodes"
  value       = aws_iam_role.node.arn
}
```

---

### 1.3 Root Configuration: `examples/hello-world`

**Purpose:** Example deployment that uses both modules and deploys a simple service

#### Files to Create

```
examples/hello-world/
├── main.tf              # Root configuration
├── variables.tf         # User-facing variables
├── outputs.tf           # User-facing outputs
├── terraform.tfvars.example  # Example values
├── hello-world.yaml     # Kubernetes manifest for hello world pod
└── README.md            # Deployment instructions
```

#### Configuration

```hcl
# main.tf
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}

provider "aws" {
  region = var.region
}

# Network infrastructure
module "network" {
  source = "../../terraform-modules/movement-network-base"

  validator_name = var.validator_name
  region         = var.region
  vpc_cidr       = var.vpc_cidr
  dns_provider   = var.dns_provider
  dns_zone_name  = var.dns_zone_name

  tags = var.tags
}

# EKS cluster infrastructure
module "eks" {
  source = "../../terraform-modules/movement-validator-infra"

  cluster_name         = "${var.validator_name}-cluster"
  kubernetes_version   = var.kubernetes_version
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  node_instance_type  = var.node_instance_type
  node_desired_size   = 1

  depends_on = [module.network]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_id,
      "--region",
      var.region
    ]
  }
}

# Deploy hello world application
resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
  }
}

resource "kubernetes_deployment" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hello-world"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello-world"
        }
      }

      spec {
        container {
          name  = "hello-world"
          image = "hashicorp/http-echo:latest"

          args = [
            "-text=Hello World from Movement Validator Infrastructure!"
          ]

          port {
            container_port = 5678
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    selector = {
      app = "hello-world"
    }

    port {
      port        = 80
      target_port = 5678
    }

    type = "LoadBalancer"
  }
}

# Create DNS record pointing to load balancer
resource "aws_route53_record" "hello_world" {
  count = var.dns_provider == "route53" ? 1 : 0

  zone_id = module.network.dns_zone_id
  name    = module.network.validator_dns_name
  type    = "A"

  alias {
    name                   = kubernetes_service.hello_world.status[0].load_balancer[0].ingress[0].hostname
    zone_id               = data.aws_elb_hosted_zone_id.main.id
    evaluate_target_health = true
  }
}

data "aws_elb_hosted_zone_id" "main" {}
```

---

### 1.4 Testing & Validation

#### Manual Testing Checklist

- [ ] Clone repository
- [ ] Copy `terraform.tfvars.example` to `terraform.tfvars`
- [ ] Configure AWS credentials
- [ ] Run `terraform init`
- [ ] Run `terraform plan` (review changes)
- [ ] Run `terraform apply` (< 15 minutes)
- [ ] Wait for load balancer to become healthy (2-5 minutes)
- [ ] Query DNS endpoint: `curl http://validator-name.region.domain.com`
- [ ] Verify "Hello World" response
- [ ] Run `terraform destroy` (cleanup)

#### Automated Tests

```bash
# tests/integration/hello-world.sh
#!/bin/bash
set -e

echo "Running M1 integration test..."

# Deploy infrastructure
cd examples/hello-world
terraform init
terraform apply -auto-approve

# Wait for service to be ready
echo "Waiting for service to be ready..."
sleep 300

# Get load balancer URL
LB_URL=$(terraform output -raw hello_world_url)

# Test endpoint
RESPONSE=$(curl -s "$LB_URL")
if [[ "$RESPONSE" == *"Hello World"* ]]; then
  echo "✓ Test passed: Hello World endpoint responding"
else
  echo "✗ Test failed: Unexpected response: $RESPONSE"
  exit 1
fi

# Cleanup
terraform destroy -auto-approve
echo "✓ M1 integration test completed successfully"
```

---

### 1.5 Documentation

#### README for Hello World Example

```markdown
# Hello World Example

This example demonstrates the core infrastructure modules by deploying a simple HTTP service.

## Prerequisites

- Terraform 1.9+
- AWS CLI configured with appropriate credentials
- AWS account with permission to create VPC, EKS, EC2

## Quick Start

1. Copy example variables:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   ```hcl
   validator_name = "alice"
   region         = "us-east-1"
   dns_zone_name  = "movementnetwork.xyz"
   ```

3. Deploy:
   ```bash
   terraform init
   terraform apply
   ```

4. Test:
   ```bash
   curl http://alice.us-east-1.movementnetwork.xyz
   # Expected: Hello World from Movement Validator Infrastructure!
   ```

5. Cleanup:
   ```bash
   terraform destroy
   ```

## Architecture

This example creates:
- VPC with public/private subnets across 2 AZs
- EKS cluster with 1 Bottlerocket node
- Network Load Balancer
- DNS A record pointing to load balancer
- Simple HTTP echo service

## Cost Estimate

- EKS control plane: ~$73/month
- EC2 c6a.4xlarge (on-demand): ~$500/month
- NAT Gateway: ~$32/month
- Network Load Balancer: ~$16/month
- **Total: ~$621/month**

Use spot instances (`enable_spot_instances = true`) to reduce costs by ~70%.
```

---

### 1.6 Deliverables

| Item | Status | Owner | Due Date |
|------|--------|-------|----------|
| `movement-network-base` module | ⬜ Not Started | | Week 1 |
| `movement-validator-infra` module | ⬜ Not Started | | Week 2 |
| `hello-world` example | ⬜ Not Started | | Week 2 |
| Module documentation | ⬜ Not Started | | Week 2 |
| Integration tests | ⬜ Not Started | | Week 3 |
| User guide | ⬜ Not Started | | Week 3 |

---

### 1.7 Exit Criteria

**Definition of Done:**

✅ All Terraform modules have passing unit tests
✅ Hello World example deploys successfully
✅ DNS resolution works and HTTP endpoint responds
✅ Infrastructure can be destroyed completely
✅ Documentation allows external user to deploy without assistance
✅ Code review completed
✅ Demo presented to stakeholders

**Ready for M2:** Core infrastructure modules are stable and tested

---

## Milestone 2: Validator Node

**Goal:** Deploy a working Aptos validator node using AWS Secrets Manager for key management.

### Objectives

- Integrate AWS Secrets Manager + External Secrets Operator
- Create Helm chart for Aptos validator
- Deploy actual Movement validator with real keys
- Validate block production
- Test failover and recovery

### Success Criteria

- [ ] Validator produces blocks successfully
- [ ] Secrets are loaded from AWS Secrets Manager
- [ ] Node can be restarted without data loss
- [ ] Metrics endpoint is accessible
- [ ] Genesis sync completes in < 30 minutes

---

### 2.1 AWS Secrets Manager Setup

#### Secret Structure

```json
{
  "validator_private_key": "0x...",
  "network_key": "0x...",
  "consensus_key": "0x...",
  "account_address": "0x...",
  "peer_id": "..."
}
```

#### Terraform Resource

```hcl
# Add to movement-validator-infra module
resource "aws_secretsmanager_secret" "validator_keys" {
  name = "movement/${var.validator_name}/keys"

  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name = "movement-${var.validator_name}-keys"
    }
  )
}

resource "aws_secretsmanager_secret_version" "validator_keys" {
  count = var.create_example_secret ? 1 : 0

  secret_id     = aws_secretsmanager_secret.validator_keys.id
  secret_string = jsonencode(var.validator_keys)
}

# IAM role for External Secrets Operator
resource "aws_iam_role" "eso" {
  name = "${var.cluster_name}-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_secrets" {
  name = "secrets-access"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_secretsmanager_secret.validator_keys.arn
    }]
  })
}
```

---

### 2.2 Helm Chart: `movement-validator`

#### Chart Structure

```
charts/movement-validator/
├── Chart.yaml
├── values.yaml
├── values.schema.json
├── README.md
├── templates/
│   ├── _helpers.tpl
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── external-secret.yaml
│   ├── configmap-validator.yaml
│   ├── pvc.yaml
│   ├── statefulset.yaml
│   └── service.yaml
└── configs/
    └── validator.yaml.tpl
```

#### Key Values

```yaml
# values.yaml
validator:
  name: "validator-01"
  nodeType: "vn"  # validator node

image:
  repository: ghcr.io/movementlabsxyz/aptos-node
  tag: "latest"
  pullPolicy: IfNotPresent

network:
  name: "devnet"
  chainId: "126"

resources:
  requests:
    cpu: "12"
    memory: "24Gi"
  limits:
    cpu: "14"
    memory: "28Gi"

storage:
  size: "500Gi"
  storageClass: "gp3-encrypted"
  iops: 6000

secrets:
  # AWS Secrets Manager configuration
  awsRegion: "us-east-1"
  secretName: "movement/validator-01/keys"

externalSecrets:
  enabled: true
  serviceAccountName: "external-secrets"
  roleArn: ""  # Provided by infrastructure module

genesis:
  # Genesis files will be downloaded from GitHub
  repository: "movementlabsxyz/movement-networks"
  branch: "main"
  network: "devnet"

monitoring:
  metricsPort: 9101
  enabled: true
```

#### StatefulSet Template (Simplified)

```yaml
# templates/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "movement-validator.fullname" . }}
  namespace: {{ .Values.namespace }}
spec:
  serviceName: {{ include "movement-validator.fullname" . }}
  replicas: 1
  selector:
    matchLabels:
      {{- include "movement-validator.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "movement-validator.labels" . | nindent 8 }}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "{{ .Values.monitoring.metricsPort }}"
    spec:
      serviceAccountName: {{ .Values.externalSecrets.serviceAccountName }}

      initContainers:
      # Download genesis files
      - name: genesis-setup
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -ex
            apk add --no-cache curl
            mkdir -p /opt/data/genesis
            curl -o /opt/data/genesis/genesis.blob \
              https://raw.githubusercontent.com/{{ .Values.genesis.repository }}/{{ .Values.genesis.branch }}/{{ .Values.network.name }}/genesis.blob
            curl -o /opt/data/genesis/waypoint.txt \
              https://raw.githubusercontent.com/{{ .Values.genesis.repository }}/{{ .Values.genesis.branch }}/{{ .Values.network.name }}/waypoint.txt
        volumeMounts:
        - name: data
          mountPath: /opt/data

      # Copy validator identity from secret
      - name: setup-identity
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -ex
            mkdir -p /opt/data/genesis
            cat /etc/secrets/validator-identity.yaml > /opt/data/genesis/validator-identity.yaml
        volumeMounts:
        - name: data
          mountPath: /opt/data
        - name: validator-secrets
          mountPath: /etc/secrets
          readOnly: true

      containers:
      - name: validator
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        command: ["aptos-node"]
        args: ["--config", "/etc/validator/validator.yaml"]

        ports:
        - name: api
          containerPort: 8080
        - name: metrics
          containerPort: {{ .Values.monitoring.metricsPort }}
        - name: vfn
          containerPort: 6181

        resources:
          {{- toYaml .Values.resources | nindent 10 }}

        volumeMounts:
        - name: data
          mountPath: /opt/data
        - name: config
          mountPath: /etc/validator

  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: {{ .Values.storage.storageClass }}
      resources:
        requests:
          storage: {{ .Values.storage.size }}
```

---

### 2.3 External Secrets Configuration

```yaml
# templates/external-secret.yaml
{{- if .Values.externalSecrets.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: {{ .Values.namespace }}
spec:
  provider:
    aws:
      service: SecretsManager
      region: {{ .Values.secrets.awsRegion }}
      auth:
        jwt:
          serviceAccountRef:
            name: {{ .Values.externalSecrets.serviceAccountName }}
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "movement-validator.fullname" . }}-keys
  namespace: {{ .Values.namespace }}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: validator-secrets
    creationPolicy: Owner
  data:
  - secretKey: validator-identity.yaml
    remoteRef:
      key: {{ .Values.secrets.secretName }}
      property: validator_identity_yaml
{{- end }}
```

---

### 2.4 Validator Config Template

Based on the reference implementation, create a config template:

```yaml
# configs/validator.yaml.tpl (will be rendered by Helm)
base:
  role: "validator"
  data_dir: "/opt/data/aptos"
  waypoint:
    from_file: "/opt/data/genesis/waypoint.txt"

consensus:
  sync_only: false
  vote_back_pressure_limit: 999999
  safety_rules:
    service:
      type: "local"
    backend:
      type: "on_disk_storage"
      path: secure-data.json
    initial_safety_rules_config:
      from_file:
        waypoint:
          from_file: /opt/data/genesis/waypoint.txt
        identity_blob_path: /opt/data/genesis/validator-identity.yaml

execution:
  genesis_file_location: "/opt/data/genesis/genesis.blob"

storage:
  rocksdb_configs:
    enable_storage_sharding: false
  storage_pruner_config:
    ledger_pruner_config:
      enable: false

validator_network:
  discovery_method: "none"
  mutual_authentication: true
  identity:
    type: "from_file"
    path: /opt/data/genesis/validator-identity.yaml

full_node_networks:
- network_id:
    private: "vfn"
  listen_address: "/ip4/0.0.0.0/tcp/6181"
  identity:
    type: "from_config"
    key: "{{ .Values.validator.vfnKey }}"
    peer_id: "{{ .Values.validator.vfnPeerId }}"

api:
  enabled: true
  address: "0.0.0.0:8080"

admin_service:
  enabled: true
  address: 127.0.0.1
  port: 9102

state_sync:
  state_sync_driver:
    bootstrapping_mode: ExecuteOrApplyFromGenesis
    continuous_syncing_mode: ExecuteTransactionsOrApplyOutputs
    enable_auto_bootstrapping: true
    max_connection_deadline_secs: 1
```

---

### 2.5 Example: Deploy Validator

```
examples/validator-single/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
└── README.md
```

```hcl
# main.tf (simplified)
module "network" {
  source = "../../terraform-modules/movement-network-base"
  # ... config
}

module "eks" {
  source = "../../terraform-modules/movement-validator-infra"
  # ... config
}

# Install External Secrets Operator
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.eso_role_arn
  }
}

# Deploy validator
resource "helm_release" "validator" {
  name      = "validator-01"
  chart     = "../../charts/movement-validator"
  namespace = "movement-l1"
  create_namespace = true

  values = [
    templatefile("${path.module}/validator-values.yaml", {
      validator_name = var.validator_name
      aws_region     = var.region
      secret_name    = module.eks.validator_secret_name
      eso_role_arn   = module.eks.eso_role_arn
    })
  ]

  depends_on = [
    helm_release.external_secrets
  ]
}
```

---

### 2.6 Testing & Validation

#### Test Checklist

- [ ] Validator pod starts successfully
- [ ] Secrets are loaded from AWS Secrets Manager
- [ ] Genesis sync completes
- [ ] Validator produces blocks
- [ ] Metrics endpoint returns data
- [ ] Pod restart preserves data
- [ ] PVC retains data after pod deletion

#### Validation Script

```bash
#!/bin/bash
# tests/validate-validator.sh

NAMESPACE="movement-l1"
POD_NAME="validator-01-0"

echo "Checking validator pod status..."
kubectl wait --for=condition=Ready pod/${POD_NAME} -n ${NAMESPACE} --timeout=600s

echo "Checking metrics endpoint..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s localhost:9101/metrics | grep "aptos_state_sync"

echo "Checking API endpoint..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s localhost:8080/v1 | jq .

echo "Checking block production..."
BLOCK_HEIGHT=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s localhost:8080/v1 | jq -r '.ledger_version')
echo "Current block height: ${BLOCK_HEIGHT}"

sleep 30

BLOCK_HEIGHT_NEW=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s localhost:8080/v1 | jq -r '.ledger_version')
echo "New block height: ${BLOCK_HEIGHT_NEW}"

if [ "${BLOCK_HEIGHT_NEW}" -gt "${BLOCK_HEIGHT}" ]; then
  echo "✓ Validator is producing blocks"
else
  echo "✗ Validator is NOT producing blocks"
  exit 1
fi
```

---

### 2.7 Deliverables

| Item | Status | Owner | Due Date |
|------|--------|-------|----------|
| AWS Secrets Manager integration | ⬜ Not Started | | Week 4 |
| External Secrets Operator setup | ⬜ Not Started | | Week 4 |
| `movement-validator` Helm chart | ⬜ Not Started | | Week 5 |
| Validator deployment example | ⬜ Not Started | | Week 5 |
| Integration tests | ⬜ Not Started | | Week 6 |
| Documentation | ⬜ Not Started | | Week 6 |

---

### 2.8 Exit Criteria

✅ Validator produces blocks in devnet
✅ Secrets management via AWS Secrets Manager works
✅ Validator survives pod restart
✅ Metrics are accessible
✅ Helm chart is documented
✅ Example deployment tested by external reviewer

**Ready for M3:** Single validator deployment is production-ready

---

## Milestone 3: VFN + Full Node

**Goal:** Deploy a complete validator cluster with Validator + VFN + optional Full Node, establishing the full network topology.

### Objectives

- Create Helm chart for VFN (Validator Full Node)
- Create Helm chart for Full Node (public API)
- Establish networking between validator → VFN → full node
- Configure Load Balancer and DNS for VFN public endpoint
- Test complete cluster deployment
- Validate data sync between nodes

### Success Criteria

- [ ] VFN syncs with validator successfully
- [ ] Full node syncs with VFN successfully
- [ ] Public API endpoint responds to queries
- [ ] Load balancer routes traffic correctly
- [ ] DNS resolves to VFN endpoint
- [ ] All nodes produce metrics

---

### 3.1 Helm Chart: `movement-vfn`

**Purpose:** Validator Full Node that connects privately to validator and exposes public fullnode network

#### Chart Structure

```
charts/movement-vfn/
├── Chart.yaml
├── values.yaml
├── values.schema.json
├── README.md
├── templates/
│   ├── _helpers.tpl
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── configmap-vfn.yaml
│   ├── pvc.yaml
│   ├── statefulset.yaml
│   ├── service-vfn.yaml
│   ├── service-lb.yaml
│   └── ingress.yaml (optional)
└── configs/
    └── vfn.yaml.tpl
```

#### Key Values

```yaml
# values.yaml
vfn:
  name: "vfn-01"
  nodeType: "vfn"  # validator full node

image:
  repository: ghcr.io/movementlabsxyz/aptos-node
  tag: "latest"
  pullPolicy: IfNotPresent

network:
  name: "devnet"
  chainId: "126"

# Connection to validator
validator:
  serviceName: "validator-01"
  namespace: "movement-l1"
  vfnPeerId: "00000000000000000000000000000000d58bc7bb154b38039bc9096ce04e1237"
  vfnPort: 6181

# VFN's own identity for public fullnode network
fullnode:
  enabled: true
  publicKey: "18FD979E14162B541B874490D47BD26BC94A398429337C536C48F5E9C8708D7B"
  peerId: "9967ebf40ac8c2ccb38709488952da1826176584ea3067b63b1695362ecb3d1f"

resources:
  requests:
    cpu: "12"
    memory: "24Gi"
  limits:
    cpu: "14"
    memory: "28Gi"

storage:
  size: "500Gi"
  storageClass: "gp3-encrypted"
  iops: 6000

# Load balancer configuration
loadBalancer:
  enabled: true
  type: "nlb"  # Network Load Balancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  ports:
    api: 8080
    fullnode: 6182

dns:
  enabled: true
  provider: "route53"  # or "cloudflare"
  zoneName: "movementnetwork.xyz"
  recordName: "vfn-01.us-east-1"

monitoring:
  metricsPort: 9101
  enabled: true
```

#### VFN Config Template

```yaml
# configs/vfn.yaml.tpl
base:
  role: "full_node"
  data_dir: "/opt/data/aptos"
  waypoint:
    from_file: "/opt/data/genesis/waypoint.txt"

execution:
  genesis_file_location: "/opt/data/genesis/genesis.blob"
  genesis_waypoint:
    from_file: "/opt/data/genesis/genesis_waypoint.txt"

storage:
  rocksdb_configs:
    enable_storage_sharding: false
  storage_pruner_config:
    ledger_pruner_config:
      enable: false

# Private network: Connect to validator
full_node_networks:
- network_id:
    private: "vfn"
  listen_address: "/ip4/0.0.0.0/tcp/6181"
  seeds:
    {{ .Values.validator.vfnPeerId }}:
      addresses:
      - "/dns/{{ .Values.validator.serviceName }}.{{ .Values.validator.namespace }}.svc.cluster.local/tcp/{{ .Values.validator.vfnPort }}/noise-ik/f0274c2774519281a8332d0bb9d8101bd58bc7bb154b38039bc9096ce04e1237/handshake/0"
      role: "Validator"

# Public network: Accept connections from full nodes
{{- if .Values.fullnode.enabled }}
- network_id: "public"
  listen_address: "/ip4/0.0.0.0/tcp/6182"
  identity:
    type: "from_config"
    key: "{{ .Values.fullnode.publicKey }}"
    peer_id: "{{ .Values.fullnode.peerId }}"
{{- end }}

admin_service:
  enabled: true
  address: 127.0.0.1
  port: 9102

api:
  enabled: true
  address: "0.0.0.0:8080"

state_sync:
  state_sync_driver:
    bootstrapping_mode: DownloadLatestStates
    continuous_syncing_mode: ApplyTransactionOutputs
```

#### Load Balancer Service

```yaml
# templates/service-lb.yaml
{{- if .Values.loadBalancer.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "movement-vfn.fullname" . }}-lb
  namespace: {{ .Values.namespace }}
  annotations:
    {{- toYaml .Values.loadBalancer.annotations | nindent 4 }}
spec:
  type: LoadBalancer
  selector:
    {{- include "movement-vfn.selectorLabels" . | nindent 4 }}
  ports:
  - name: api
    port: {{ .Values.loadBalancer.ports.api }}
    targetPort: 8080
    protocol: TCP
  - name: fullnode
    port: {{ .Values.loadBalancer.ports.fullnode }}
    targetPort: 6182
    protocol: TCP
{{- end }}
```

---

### 3.2 Helm Chart: `movement-fullnode`

**Purpose:** Public full node that connects to VFN and provides API access

#### Key Values

```yaml
# values.yaml
fullnode:
  name: "fullnode-01"
  nodeType: "fn"  # full node

image:
  repository: ghcr.io/movementlabsxyz/aptos-node
  tag: "latest"

network:
  name: "devnet"
  chainId: "126"

# Connection to VFN
vfn:
  serviceName: "vfn-01-lb"  # Connect via load balancer
  namespace: "movement-l1"
  peerId: "9967ebf40ac8c2ccb38709488952da1826176584ea3067b63b1695362ecb3d1f"
  port: 6182

resources:
  requests:
    cpu: "8"
    memory: "16Gi"
  limits:
    cpu: "10"
    memory: "20Gi"

storage:
  size: "500Gi"
  storageClass: "gp3-encrypted"

# Full nodes are optional for external use
loadBalancer:
  enabled: false  # Usually behind VFN

monitoring:
  metricsPort: 9101
  enabled: true
```

#### Full Node Config Template

```yaml
# configs/fullnode.yaml.tpl
base:
  role: "full_node"
  data_dir: "/opt/data/aptos"
  waypoint:
    from_file: "/opt/data/genesis/waypoint.txt"

execution:
  genesis_file_location: "/opt/data/genesis/genesis.blob"
  genesis_waypoint:
    from_file: "/opt/data/genesis/genesis_waypoint.txt"

storage:
  rocksdb_configs:
    enable_storage_sharding: false
  storage_pruner_config:
    ledger_pruner_config:
      enable: false

# Connect to VFN on public network
full_node_networks:
- network_id: "public"
  discovery_method: "none"
  listen_address: "/ip4/0.0.0.0/tcp/6182"
  seeds:
    {{ .Values.vfn.peerId | upper }}:
      addresses:
        - "/dns/{{ .Values.vfn.serviceName }}.{{ .Values.vfn.namespace }}.svc.cluster.local/tcp/{{ .Values.vfn.port }}/noise-ik/{{ .Values.vfn.peerId | upper }}/handshake/0"
      role: "Upstream"

api:
  enabled: true
  address: 0.0.0.0:8080

state_sync:
  state_sync_driver:
    bootstrapping_mode: DownloadLatestStates
    continuous_syncing_mode: ApplyTransactionOutputs
```

---

### 3.3 Example: Complete Validator Cluster

```
examples/validator-cluster/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── validator-values.yaml
├── vfn-values.yaml
├── fullnode-values.yaml (optional)
└── README.md
```

#### Main Configuration

```hcl
# main.tf
# ... (reuse network + eks modules from M1/M2)

# Deploy validator
resource "helm_release" "validator" {
  name      = "validator-01"
  chart     = "../../charts/movement-validator"
  namespace = "movement-l1"
  create_namespace = true

  values = [file("${path.module}/validator-values.yaml")]
}

# Deploy VFN (connected to validator)
resource "helm_release" "vfn" {
  name      = "vfn-01"
  chart     = "../../charts/movement-vfn"
  namespace = "movement-l1"

  values = [file("${path.module}/vfn-values.yaml")]

  depends_on = [helm_release.validator]
}

# Deploy Full Node (optional, connected to VFN)
resource "helm_release" "fullnode" {
  count = var.deploy_fullnode ? 1 : 0

  name      = "fullnode-01"
  chart     = "../../charts/movement-fullnode"
  namespace = "movement-l1"

  values = [file("${path.module}/fullnode-values.yaml")]

  depends_on = [helm_release.vfn]
}

# DNS record for VFN
data "kubernetes_service" "vfn_lb" {
  metadata {
    name      = "vfn-01-lb"
    namespace = "movement-l1"
  }

  depends_on = [helm_release.vfn]
}

resource "aws_route53_record" "vfn" {
  zone_id = module.network.dns_zone_id
  name    = "vfn-01.${var.region}.${var.dns_zone_name}"
  type    = "A"

  alias {
    name                   = data.kubernetes_service.vfn_lb.status[0].load_balancer[0].ingress[0].hostname
    zone_id               = data.aws_elb_hosted_zone_id.main.id
    evaluate_target_health = true
  }
}
```

---

### 3.4 Network Topology Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/20)                    │
│                                                         │
│  ┌────────────────────────────────────────────────┐   │
│  │            EKS Cluster: validator-alice         │   │
│  │                                                 │   │
│  │  ┌──────────────┐    Private VFN Network      │   │
│  │  │ Validator    │◄──────────────────┐         │   │
│  │  │   (vn-01)    │      Port 6181     │         │   │
│  │  │              │                     │         │   │
│  │  │ • Produces   │                     │         │   │
│  │  │   blocks     │                     │         │   │
│  │  │ • No public  │                  ┌──▼─────┐  │   │
│  │  │   access     │                  │  VFN   │  │   │
│  │  └──────────────┘                  │(vfn-01)│  │   │
│  │                                    │        │  │   │
│  │                                    │ • Syncs│  │   │
│  │                                    │   from │  │   │
│  │                                    │   VN   │  │   │
│  │                                    │ • Public│  │   │
│  │                                    │   API  │  │   │
│  │                                    └───┬────┘  │   │
│  │                                        │       │   │
│  │                Public Fullnode Network │       │   │
│  │                      Port 6182         │       │   │
│  │                                        │       │   │
│  │                                   ┌────▼────┐ │   │
│  │                                   │Fullnode │ │   │
│  │                                   │ (fn-01) │ │   │
│  │                                   │         │ │   │
│  │                                   │• Syncs  │ │   │
│  │                                   │  from   │ │   │
│  │                                   │  VFN    │ │   │
│  │                                   │• Optional│ │   │
│  │                                   └─────────┘ │   │
│  └────────────────────────────────────────────────┘   │
│                          ▲                             │
│                          │                             │
│  ┌───────────────────────┴────────────────────────┐   │
│  │    Network Load Balancer (Public)              │   │
│  │    • Port 8080 (API)                           │   │
│  │    • Port 6182 (P2P)                           │   │
│  └────────────────────────────────────────────────┘   │
│                          ▲                             │
└──────────────────────────┼─────────────────────────────┘
                           │
                           │
               ┌───────────┴──────────┐
               │   Route53 DNS        │
               │                      │
               │ vfn-01.us-east-1.   │
               │ movementnetwork.xyz  │
               └──────────────────────┘
```

---

### 3.5 Testing & Validation

#### Test Scenarios

**TC-1: Validator → VFN Sync**
```bash
# Check VFN syncing from validator
kubectl exec -n movement-l1 vfn-01-0 -- curl -s localhost:8080/v1 | jq '.ledger_version'

# Compare with validator
kubectl exec -n movement-l1 validator-01-0 -- curl -s localhost:8080/v1 | jq '.ledger_version'

# Should be within 10 blocks
```

**TC-2: VFN → Full Node Sync**
```bash
# Check fullnode syncing from VFN
kubectl exec -n movement-l1 fullnode-01-0 -- curl -s localhost:8080/v1 | jq '.ledger_version'

# Should be within 50 blocks of VFN
```

**TC-3: Public API Access**
```bash
# Test via load balancer
VFN_URL=$(terraform output -raw vfn_url)
curl -s ${VFN_URL}/v1 | jq .

# Test DNS resolution
curl -s https://vfn-01.us-east-1.movementnetwork.xyz/v1 | jq .
```

**TC-4: Network Connectivity**
```bash
# Verify validator is NOT publicly accessible
kubectl get svc -n movement-l1 validator-01
# Should be ClusterIP only

# Verify VFN has load balancer
kubectl get svc -n movement-l1 vfn-01-lb
# Should have EXTERNAL-IP
```

#### Integration Test Script

```bash
#!/bin/bash
# tests/validate-cluster.sh
set -e

NAMESPACE="movement-l1"

echo "=== M3 Integration Test: Complete Cluster ==="

# Wait for all pods
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pod/validator-01-0 -n ${NAMESPACE} --timeout=600s
kubectl wait --for=condition=Ready pod/vfn-01-0 -n ${NAMESPACE} --timeout=600s
kubectl wait --for=condition=Ready pod/fullnode-01-0 -n ${NAMESPACE} --timeout=600s

# Get block heights
echo "Checking block heights..."
VN_HEIGHT=$(kubectl exec -n ${NAMESPACE} validator-01-0 -- curl -s localhost:8080/v1 | jq -r '.ledger_version')
VFN_HEIGHT=$(kubectl exec -n ${NAMESPACE} vfn-01-0 -- curl -s localhost:8080/v1 | jq -r '.ledger_version')
FN_HEIGHT=$(kubectl exec -n ${NAMESPACE} fullnode-01-0 -- curl -s localhost:8080/v1 | jq -r '.ledger_version')

echo "Validator height: ${VN_HEIGHT}"
echo "VFN height: ${VFN_HEIGHT}"
echo "Fullnode height: ${FN_HEIGHT}"

# Validate sync (VFN should be within 10 blocks of validator)
DIFF=$((VN_HEIGHT - VFN_HEIGHT))
if [ ${DIFF#-} -le 10 ]; then
  echo "✓ VFN is in sync with validator (diff: ${DIFF})"
else
  echo "✗ VFN is out of sync (diff: ${DIFF})"
  exit 1
fi

# Test public endpoint
echo "Testing public VFN endpoint..."
VFN_LB=$(kubectl get svc -n ${NAMESPACE} vfn-01-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
RESPONSE=$(curl -s http://${VFN_LB}:8080/v1)
LB_HEIGHT=$(echo ${RESPONSE} | jq -r '.ledger_version')

if [ "${LB_HEIGHT}" -gt 0 ]; then
  echo "✓ Public endpoint is accessible (height: ${LB_HEIGHT})"
else
  echo "✗ Public endpoint failed"
  exit 1
fi

echo "=== All M3 tests passed ==="
```

---

### 3.6 Deliverables

| Item | Status | Owner | Due Date |
|------|--------|-------|----------|
| `movement-vfn` Helm chart | ⬜ Not Started | | Week 7 |
| `movement-fullnode` Helm chart | ⬜ Not Started | | Week 7 |
| Load balancer configuration | ⬜ Not Started | | Week 8 |
| DNS integration | ⬜ Not Started | | Week 8 |
| Complete cluster example | ⬜ Not Started | | Week 8 |
| Network topology tests | ⬜ Not Started | | Week 9 |
| Documentation | ⬜ Not Started | | Week 9 |

---

### 3.7 Exit Criteria

✅ Complete validator cluster deploys successfully
✅ VFN syncs with validator (< 10 block lag)
✅ Full node syncs with VFN (< 50 block lag)
✅ Public API is accessible via load balancer
✅ DNS resolves to VFN endpoint
✅ All components survive pod restarts
✅ Network isolation verified (validator not public)

**Ready for M4:** Production-ready validator cluster with public API access

---

## Milestone 4: Observability Cluster

**Goal:** Deploy a separate observability cluster with push-based metrics and logs collection, completely decoupled from validator infrastructure.

### Objectives

- Deploy dedicated observability EKS cluster
- Install VictoriaMetrics for metrics storage
- Install Loki for log aggregation
- Install Grafana for visualization
- Configure NGINX Ingress for public HTTPS endpoints
- Integrate validators to push metrics/logs
- Create operational dashboards

### Success Criteria

- [ ] Observability cluster operational
- [ ] Validators push metrics successfully
- [ ] Logs are aggregated from all nodes
- [ ] Grafana dashboards display validator metrics
- [ ] Public HTTPS endpoints secured with TLS
- [ ] 13-month metrics retention working
- [ ] Alerts configured for critical issues

---

### 4.1 Observability Cluster Infrastructure

#### Architecture

```
┌────────────────────────────────────────────────────┐
│      Observability VPC (10.10.0.0/20)             │
│                                                    │
│  ┌──────────────────────────────────────────┐    │
│  │   EKS Cluster: movement-observability     │    │
│  │                                           │    │
│  │   ┌────────────────────────────────┐     │    │
│  │   │  NGINX Ingress Controller      │     │    │
│  │   │  • TLS termination             │     │    │
│  │   │  • Rate limiting               │     │    │
│  │   └────────┬───────────────────────┘     │    │
│  │            │                              │    │
│  │   ┌────────▼─────────┐  ┌──────────────┐│    │
│  │   │  VictoriaMetrics │  │     Loki     ││    │
│  │   │  • Metrics store │  │  • Log store ││    │
│  │   │  • 13mo retention│  │  • 30d retain││    │
│  │   └──────────────────┘  └──────────────┘│    │
│  │                                           │    │
│  │   ┌──────────────────────────────────┐   │    │
│  │   │          Grafana                  │   │    │
│  │   │  • Visualization                  │   │    │
│  │   │  • Dashboards                     │   │    │
│  │   │  • Alerting                       │   │    │
│  │   └──────────────────────────────────┘   │    │
│  └──────────────────────────────────────────┘    │
│                     ▲                             │
│                     │                             │
│  ┌──────────────────┴─────────────────────────┐  │
│  │    Network Load Balancer (Public)          │  │
│  │    obs.movementnetwork.xyz                 │  │
│  │    • /api/v1/write → VictoriaMetrics       │  │
│  │    • /loki/api/v1/push → Loki              │  │
│  │    • /grafana → Grafana                    │  │
│  └────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
                       ▲
                       │ HTTPS Push
        ┌──────────────┴─────────────┐
        │                            │
┌───────▼─────────┐      ┌──────────▼────────┐
│ Validator VPC-A │      │ Validator VPC-B   │
│ • Push metrics  │      │ • Push metrics    │
│ • Push logs     │      │ • Push logs       │
└─────────────────┘      └───────────────────┘
```

---

### 4.2 Terraform Module: `movement-observability`

#### Files to Create

```
terraform-modules/movement-observability/
├── main.tf
├── variables.tf
├── outputs.tf
├── vpc.tf                 # Dedicated VPC for observability
├── eks.tf                 # EKS cluster
├── storage.tf             # EBS volumes for VictoriaMetrics/Loki
├── dns.tf                 # Public DNS for ingress
├── versions.tf
└── README.md
```

#### Key Resources

- VPC with CIDR `10.10.0.0/20` (separate from validator VPCs)
- EKS cluster with 2-3 nodes (m5.2xlarge)
- Large EBS volumes for metrics/logs storage
- NLB for public ingress
- DNS records for `obs.movementnetwork.xyz`

---

### 4.3 Helm Charts Configuration

#### VictoriaMetrics Deployment

```yaml
# observability-values/victoria-metrics.yaml
victoria-metrics-cluster:
  enabled: true

  vmselect:
    replicaCount: 2
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"

  vminsert:
    replicaCount: 2
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"

  vmstorage:
    replicaCount: 2
    retentionPeriod: "13"  # 13 months
    resources:
      requests:
        cpu: "4"
        memory: "8Gi"
        storage: "1Ti"
    persistentVolume:
      enabled: true
      storageClass: "gp3-encrypted"
      size: "1Ti"

  # Remote write endpoint
  vminsert:
    service:
      annotations:
        external-dns.alpha.kubernetes.io/hostname: "metrics.obs.movementnetwork.xyz"
```

#### Loki Deployment

```yaml
# observability-values/loki.yaml
loki:
  enabled: true

  storage:
    type: "s3"
    bucketNames:
      chunks: "movement-loki-chunks"
      ruler: "movement-loki-ruler"
    s3:
      region: "us-east-1"
      insecure: false

  limits_config:
    retention_period: "720h"  # 30 days

  compactor:
    enabled: true
    retention_enabled: true

  ingester:
    replicas: 2
    persistence:
      enabled: true
      size: "100Gi"

  querier:
    replicas: 2

  query_frontend:
    replicas: 2
```

#### Grafana Deployment

```yaml
# observability-values/grafana.yaml
grafana:
  enabled: true

  adminPassword: "${ADMIN_PASSWORD}"  # From secret

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: VictoriaMetrics
        type: prometheus
        url: http://victoria-metrics-cluster-vmselect:8481/select/0/prometheus
        isDefault: true
        editable: false

      - name: Loki
        type: loki
        url: http://loki-gateway
        editable: false

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: 'Movement'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

  dashboards:
    default:
      validator-overview:
        gnetId: 12345  # Custom dashboard ID
        datasource: VictoriaMetrics

      node-exporter:
        gnetId: 1860
        datasource: VictoriaMetrics

  persistence:
    enabled: true
    size: "10Gi"

  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "2Gi"
```

#### NGINX Ingress

```yaml
# observability-values/nginx-ingress.yaml
controller:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"

  resources:
    requests:
      cpu: "1"
      memory: "2Gi"

  config:
    enable-real-ip: "true"
    use-forwarded-headers: "true"
    proxy-body-size: "100m"

  metrics:
    enabled: true

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5
```

---

### 4.4 Ingress Configuration

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: observability-ingress
  namespace: observability
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - obs.movementnetwork.xyz
    secretName: obs-tls
  rules:
  - host: obs.movementnetwork.xyz
    http:
      paths:
      # VictoriaMetrics remote write endpoint
      - path: /api/v1/write
        pathType: Prefix
        backend:
          service:
            name: victoria-metrics-cluster-vminsert
            port:
              number: 8480

      # Loki push endpoint
      - path: /loki/api/v1/push
        pathType: Prefix
        backend:
          service:
            name: loki-gateway
            port:
              number: 80

      # Grafana UI
      - path: /grafana
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
```

---

### 4.5 Validator Integration

#### Add to Validator Helm Chart

```yaml
# charts/movement-validator/values.yaml (additions)
monitoring:
  pushMetrics:
    enabled: true
    endpoint: "https://obs.movementnetwork.xyz/api/v1/write"
    interval: "15s"

logging:
  fluentBit:
    enabled: true
    lokiEndpoint: "https://obs.movementnetwork.xyz/loki/api/v1/push"
```

#### Fluent Bit DaemonSet

```yaml
# templates/fluent-bit.yaml
{{- if .Values.logging.fluentBit.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: {{ .Values.namespace }}
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Daemon        off
        Log_Level     info

    [INPUT]
        Name              tail
        Path              /var/log/containers/*_movement-l1_*.log
        Parser            docker
        Tag               kube.*

    [OUTPUT]
        Name              loki
        Match             *
        Host              obs.movementnetwork.xyz
        Port              443
        TLS               On
        Labels            job=fluentbit, cluster=${CLUSTER_NAME}
        Label_Keys        $kubernetes['pod_name'],$kubernetes['namespace_name'],$kubernetes['container_name']
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: {{ .Values.namespace }}
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      containers:
      - name: fluent-bit
        image: grafana/fluent-bit-plugin-loki:2.9.0
        env:
        - name: CLUSTER_NAME
          value: {{ .Values.validator.name }}
        volumeMounts:
        - name: config
          mountPath: /fluent-bit/etc/
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: fluent-bit-config
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
{{- end }}
```

#### Prometheus Remote Write

```yaml
# Add to validator pod as sidecar or use built-in metrics push
env:
- name: PUSH_METRICS_ENDPOINT
  value: "https://obs.movementnetwork.xyz/api/v1/write"
- name: PUSH_METRICS_INTERVAL
  value: "15s"
```

---

### 4.6 Grafana Dashboards

#### Validator Overview Dashboard

Create dashboard JSON with panels for:

1. **Block Production Rate**
   - Query: `rate(aptos_consensus_committed_blocks[5m])`
   - Visualization: Graph

2. **Transaction Throughput**
   - Query: `rate(aptos_consensus_committed_txns[5m])`
   - Visualization: Graph

3. **Sync Status**
   - Query: `aptos_state_sync_version{type="synced"}`
   - Visualization: Gauge

4. **Memory Usage**
   - Query: `container_memory_usage_bytes{pod=~"validator.*"}`
   - Visualization: Graph

5. **Disk I/O**
   - Query: `rate(container_fs_writes_bytes_total[5m])`
   - Visualization: Graph

6. **API Latency (P99)**
   - Query: `histogram_quantile(0.99, rate(aptos_api_request_duration_seconds_bucket[5m]))`
   - Visualization: Graph

7. **Error Rate**
   - Query: `rate(aptos_api_requests_total{status=~"5.."}[5m])`
   - Visualization: Graph

8. **Peer Connections**
   - Query: `aptos_network_peers`
   - Visualization: Stat

---

### 4.7 Deployment Example

```
examples/observability-cluster/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
└── README.md
```

```hcl
# main.tf
module "observability_network" {
  source = "../../terraform-modules/movement-network-base"

  validator_name = "observability"
  region         = var.region
  vpc_cidr       = "10.10.0.0/20"
  dns_zone_name  = var.dns_zone_name
}

module "observability_cluster" {
  source = "../../terraform-modules/movement-observability"

  cluster_name       = "movement-observability"
  vpc_id            = module.observability_network.vpc_id
  private_subnet_ids = module.observability_network.private_subnet_ids
  node_instance_type = "m5.2xlarge"
  node_desired_size  = 3
}

# Install VictoriaMetrics
resource "helm_release" "victoria_metrics" {
  name       = "victoria-metrics"
  repository = "https://victoriametrics.github.io/helm-charts"
  chart      = "victoria-metrics-cluster"
  namespace  = "observability"
  create_namespace = true

  values = [file("${path.module}/victoria-metrics.yaml")]
}

# Install Loki
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = "observability"

  values = [file("${path.module}/loki.yaml")]

  depends_on = [helm_release.victoria_metrics]
}

# Install Grafana
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "observability"

  values = [file("${path.module}/grafana.yaml")]

  depends_on = [
    helm_release.victoria_metrics,
    helm_release.loki
  ]
}

# Install NGINX Ingress
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace = true

  values = [file("${path.module}/nginx-ingress.yaml")]
}

# Install cert-manager for TLS
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}
```

---

### 4.8 Testing & Validation

#### Test Script

```bash
#!/bin/bash
# tests/validate-observability.sh
set -e

NAMESPACE="observability"
OBS_URL="https://obs.movementnetwork.xyz"

echo "=== M4 Integration Test: Observability Cluster ==="

# Check all pods are running
echo "Checking pod status..."
kubectl wait --for=condition=Ready pod -l app=victoria-metrics -n ${NAMESPACE} --timeout=300s
kubectl wait --for=condition=Ready pod -l app=loki -n ${NAMESPACE} --timeout=300s
kubectl wait --for=condition=Ready pod -l app=grafana -n ${NAMESPACE} --timeout=300s

# Test VictoriaMetrics write endpoint
echo "Testing metrics push endpoint..."
curl -X POST "${OBS_URL}/api/v1/write" \
  -H "Content-Type: application/x-protobuf" \
  --data-binary @test-metrics.pb \
  -v

# Test Loki push endpoint
echo "Testing log push endpoint..."
curl -X POST "${OBS_URL}/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)000000000'","test log"]]}]}' \
  -v

# Test Grafana access
echo "Testing Grafana UI..."
GRAFANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${OBS_URL}/grafana/api/health")
if [ "${GRAFANA_STATUS}" == "200" ]; then
  echo "✓ Grafana is accessible"
else
  echo "✗ Grafana health check failed (HTTP ${GRAFANA_STATUS})"
  exit 1
fi

echo "=== All M4 tests passed ==="
```

---

### 4.9 Deliverables

| Item | Status | Owner | Due Date |
|------|--------|-------|----------|
| Observability infrastructure module | ⬜ Not Started | | Week 10 |
| VictoriaMetrics deployment | ⬜ Not Started | | Week 10 |
| Loki deployment | ⬜ Not Started | | Week 11 |
| Grafana deployment | ⬜ Not Started | | Week 11 |
| NGINX Ingress + TLS | ⬜ Not Started | | Week 11 |
| Validator integration (push) | ⬜ Not Started | | Week 12 |
| Grafana dashboards | ⬜ Not Started | | Week 12 |
| Integration tests | ⬜ Not Started | | Week 12 |
| Documentation | ⬜ Not Started | | Week 12 |

---

### 4.10 Exit Criteria

✅ Observability cluster deployed independently
✅ Validators push metrics to VictoriaMetrics
✅ Logs flow to Loki from all nodes
✅ Grafana displays real-time validator metrics
✅ Public HTTPS endpoints secured with TLS
✅ 13-month metrics retention verified
✅ Dashboards created for all key metrics
✅ Alerting configured for critical conditions
✅ Load testing validates performance under load

**Project Complete:** Full infrastructure redesign delivered

---

## Overall Project Timeline

```
Week 1-3:   M1 - Foundation & Hello World
Week 4-6:   M2 - Validator Node
Week 7-9:   M3 - VFN + Full Node
Week 10-12: M4 - Observability Cluster
Week 13:    Final testing & documentation
Week 14:    Public release & community onboarding
```

---

## Success Metrics

### Technical Metrics

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Deployment Time | < 15 min | TBD | ⬜ |
| Block Production Latency | < 1s | TBD | ⬜ |
| API Response Time (P99) | < 200ms | TBD | ⬜ |
| Uptime SLA | 99.9% | TBD | ⬜ |
| Test Coverage | > 80% | TBD | ⬜ |

### Adoption Metrics

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| External Deployments | 5 orgs | 0 | ⬜ |
| GitHub Stars | 100+ | TBD | ⬜ |
| Documentation Completeness | 100% | TBD | ⬜ |
| Community Contributors | 10+ | 0 | ⬜ |

---

## Risk Management

### High Priority Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| AWS Secrets Manager adoption barrier | High | Provide migration scripts from other secret stores |
| Terraform learning curve for users | Medium | Comprehensive examples and video tutorials |
| EKS cost concerns | High | Document spot instance usage, provide cost calculator |
| VPC per validator IP exhaustion | Low | Use smaller CIDR blocks, document best practices |
| Observability cluster single point of failure | Medium | Deploy in HA mode with multi-AZ |

---

## Dependencies

### External Dependencies

- AWS EKS availability in target regions
- Terraform 1.9+ features
- Helm chart repositories accessibility
- GitHub for genesis file hosting
- DNS provider (Route53 or Cloudflare)

### Internal Dependencies

- Validator key generation process
- Genesis blob availability
- Movement network specifications
- Container images published to GHCR

---

## Appendix: Quick Reference

### Repository Structure

```
movement-validator-infrastructure/
├── terraform-modules/
│   ├── movement-network-base/
│   ├── movement-validator-infra/
│   └── movement-observability/
├── charts/
│   ├── movement-validator/
│   ├── movement-vfn/
│   └── movement-fullnode/
├── examples/
│   ├── hello-world/
│   ├── validator-single/
│   ├── validator-cluster/
│   └── observability-cluster/
├── tests/
│   ├── unit/
│   └── integration/
└── docs/
    ├── getting-started.md
    ├── deployment-guide.md
    ├── architecture.md
    └── troubleshooting.md
```

### Key Commands

```bash
# Deploy hello world
cd examples/hello-world
terraform init && terraform apply

# Deploy validator
cd examples/validator-single
terraform init && terraform apply

# Deploy full cluster
cd examples/validator-cluster
terraform init && terraform apply

# Deploy observability
cd examples/observability-cluster
terraform init && terraform apply

# Run tests
./tests/integration/validate-all.sh

# Cleanup
terraform destroy -auto-approve
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-30 | Infrastructure Team | Initial milestone plan |

**Next Review Date:** Weekly during implementation

**Approval Required From:**
- [ ] Technical Lead
- [ ] Product Owner
- [ ] Security Team
- [ ] DevOps Lead

---

**END OF MILESTONE PLAN**
