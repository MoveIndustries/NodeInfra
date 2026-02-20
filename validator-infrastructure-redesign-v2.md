# Movement Validator Infrastructure Redesign

## Design Document for Modular, Reusable Validator Provisioning

**Document Version:** 2.1
**Date:** 2026-01-30
**Author:** Infrastructure Team
**Status:** Design Phase

---

## Executive Summary

This document outlines a comprehensive redesign of the Movement Network validator infrastructure from CDKTF TypeScript to native Terraform HCL, enabling modular, independent provisioning of validator instances with corresponding VFNs and Full Nodes. The redesign transforms internal-only infrastructure into a public, reusable solution that external organizations and independent builders can adopt with their own AWS accounts, validator keys, and S3 buckets.

### Key Objectives

1. **Modularity:** Deploy single validator + VFN + Full Node independently
2. **Reusability:** Public Terraform modules usable by any organization
3. **Native Terraform:** Latest Terraform 1.9+ (no CDKTF complexity)
4. **Flexibility:** Support custom validator keys, S3 buckets, AWS accounts
5. **Security:** AWS Secrets Manager with External Secrets Operator
6. **Isolation:** One VPC per validator cluster for complete independence

---

## 1. Requirements

### 1.1 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | Deploy single validator independently | **Critical** |
| FR-2 | Deploy VFN connected to specific validator | **Critical** |
| FR-3 | Deploy Full Node for RPC/API access | **Critical** |
| FR-4 | Support multiple validator instances in parallel | **High** |
| FR-5 | Allow external users to use their own AWS credentials | **Critical** |
| FR-6 | Support custom validator keys and genesis files | **Critical** |
| FR-7 | Support multi-region deployment | **Medium** |
| FR-8 | Each validator cluster has its own VPC | **Critical** |
| FR-9 | Provide built-in monitoring (Prometheus/Grafana) | **High** |
| FR-10 | Support upgrades without downtime (VFN failover) | **Medium** |

### 1.2 Non-Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-1 | Infrastructure code must be public (MIT licensed) | **Critical** |
| NFR-2 | No hardcoded credentials or org-specific values | **Critical** |
| NFR-3 | Support Terraform 1.9+ (native HCL, no CDKTF) | **Critical** |
| NFR-4 | Clear documentation for external adoption | **Critical** |
| NFR-5 | Deployment time < 15 minutes per validator | **High** |
| NFR-6 | Support cost optimization (spot instances, autoscaling) | **Medium** |
| NFR-7 | Extensible for other blockchains beyond Movement | **Low** |

### 1.3 Design Principles

1. **Separation of Concerns:** Infrastructure, configuration, and application layers are independent
2. **Single Responsibility:** Each module does one thing well
3. **Idempotency:** Re-running deployments produces consistent results
4. **Immutability:** Infrastructure changes via code, not manual modifications
5. **Security by Default:** Least privilege, encrypted secrets, network isolation
6. **Cloud Agnostic (where possible):** Kubernetes patterns work across clouds
7. **One VPC Per Validator:** Complete network isolation between validators

---

## 2. Existing Infrastructure and Its Problems

### 2.1 Current Architecture Overview

Movement validator infrastructure is currently managed across two CDKTF (TypeScript) repositories:

```
┌─────────────────────────────────────────────────────────────┐
│                    cdktf-compute                            │
│            (Infrastructure - TypeScript/CDKTF)              │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ClustersStack.ts (2,236 lines)                     │   │
│  │  • EKS cluster (movement-network)                   │   │
│  │  • Self-managed node groups (Bottlerocket):         │   │
│  │    - aptos-vn (c6a.4xlarge) - Validator nodes       │   │
│  │    - aptos-vfn (c6a.4xlarge) - VFN nodes            │   │
│  │    - aptos-fn (c6a.4xlarge) - Full nodes            │   │
│  │    - default, loki, mimir node groups               │   │
│  │  • Observability stack (Prometheus, Loki, Mimir)    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Consumes: EKS cluster endpoint
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 cdktf-mvmt-networks                         │
│            (Application - TypeScript/CDKTF)                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  MvmtNetworkStack (environments.yaml)               │   │
│  │                                                     │   │
│  │  devnet.aptosNodes:                                │   │
│  │    vn-01: (Validator Node)                         │   │
│  │      nodeType: vn                                  │   │
│  │      image: ghcr.io/movementlabsxyz/aptos-node     │   │
│  │      resources: 12 CPU, 24Gi memory                │   │
│  │      storageSize: 100Gi                            │   │
│  │                                                     │   │
│  │    vfn-01: (Validator Full Node)                   │   │
│  │      nodeType: vfn                                 │   │
│  │      networking.fullnode.enabled: true             │   │
│  │      (NLB + DNS for public access)                 │   │
│  │                                                     │   │
│  │    pfn-backup: (Public Full Node Backup)           │   │
│  │      nodeType: fn-backup                           │   │
│  │      backupS3Bucket: movement-pfn-backups-devnet   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Repository Overview

#### **cdktf-compute** (Infrastructure Layer)
- **Purpose:** Provisions EKS clusters, node groups, observability stack
- **Technology:** CDKTF (TypeScript) with 2,236-line `ClustersStack.ts`
- **Configuration:** `environments.jsonc` (1,583 lines) for all environments
- **Manages:** EKS clusters, node groups, observability, WAF

#### **cdktf-mvmt-networks** (Application Layer)
- **Purpose:** Deploys validator/VFN/full node applications with networking
- **Technology:** CDKTF (TypeScript) with `MvmtNetworkStack`
- **Configuration:** `environments.yaml` for per-node validator configuration
- **Manages:** Validator deployments, Ingress, DNS, TLS certificates

#### **cdktf-environments** (Foundation Layer)
- **Purpose:** AWS Organizations multi-account setup, networking foundation
- **Manages:** VPC creation, CIDR allocation, HCP integration, IAM roles

### 2.3 Problems Identified

#### **Problem 1: CDKTF Complexity**
- TypeScript → JSON → Terraform translation adds unnecessary complexity
- 2,236-line monolithic stack difficult to maintain
- External users must learn CDKTF (not just Terraform)
- Limited testing capabilities (no native Terraform test framework)

#### **Problem 2: Tight Coupling**
- Single ClustersStack contains EKS + observability + backup + compute
- Cannot deploy observability independently of validators
- Shared node groups across multiple validators (limited isolation)
- Shared VPC across all validators in an environment

#### **Problem 3: Configuration Sprawl**
- 1,583-line `environments.jsonc` mixes infrastructure with app config
- Separate `environments.yaml` for validator deployment
- Two sources of truth for environment configuration
- Complex CIDR calculation logic

#### **Problem 4: Not Reusable**
- Hardcoded Movement-specific values throughout
- Requires Movement's Terraform Cloud workspace and 1Password access
- No public modules external organizations can consume
- Tight coupling to Movement's AWS Organizations structure
- HCP Vault/HVN dependency requires expensive infrastructure

#### **Problem 5: Shared Networking**
- All validators in an environment share a single VPC
- Cannot deploy validators independently
- Network failures affect all validators
- IP address coordination required


---

## 3. New Architecture Overview

### 3.1 High-Level Architecture

```
┌────────────────────────────────────────────────────────────────┐
│              External Validator Operator (Any Organization)     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Terraform Configuration                      │  │
│  │  (validator-specific, in operator's own repo)           │  │
│  └───────────┬──────────────────────────────────────────────┘  │
│              │                                                   │
│              │  Calls Public Terraform Modules                  │
│              │                                                   │
│  ┌───────────▼──────────────┐  ┌──────────────────────────┐   │
│  │  movement-network-base   │  │  movement-validator-infra│   │
│  │  (Public Module)         │  │  (Public Module)         │   │
│  │  • VPC per validator     │  │  • EKS cluster           │   │
│  │  • Subnets               │  │  • Node groups           │   │
│  │  • Security groups       │  │  • Storage (EBS)         │   │
│  │  • DNS (optional)        │  │  • IAM roles (IRSA)      │   │
│  └───────────┬──────────────┘  └───────────┬──────────────┘   │
│              │                              │                   │
│              │  Outputs: VPC, subnets       │  Outputs: EKS    │
│              └──────────────┬───────────────┘                   │
│                             │                                   │
│              ┌──────────────▼──────────────────────────────┐   │
│              │         Helm Chart Deployment               │   │
│              │  ┌─────────────┐  ┌─────────────┐          │   │
│              │  │ Validator   │  │     VFN     │          │   │
│              │  │  (Public)   │  │  (Public)   │          │   │
│              │  └─────────────┘  └─────────────┘          │   │
│              └─────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         AWS Secrets Manager (in operator's account)      │  │
│  │  • Validator private keys                                │  │
│  │  • Network keys                                          │  │
│  │  • Genesis configuration                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

### 3.2 Key Architectural Changes

| Aspect | Current | New Design |
|--------|---------|------------|
| **IaC Tool** | CDKTF (TypeScript) | Native Terraform HCL |
| **Networking** | Shared VPC per environment | **One VPC per validator cluster** |
| **Modularity** | Monolithic stacks | Independent modules per validator |
| **Secret Management** | 1Password + scripts | AWS Secrets Manager + ESO |
| **Observability** | Tightly coupled | Decoupled push-based |
| **Deployment Model** | Internal only | Public modules for external validators |
| **IP Management** | Centralized CIDR allocation | **No coordination (IPs can overlap)** |
| **DNS** | Shared zones | **One DNS name per validator** |

### 3.3 Technology Stack

#### **Infrastructure as Code: Terraform 1.9+ (Native HCL)**

**Why Drop CDKTF?**
- **Learning Curve:** Terraform HCL only (no TypeScript required)
- **External Adoption:** Standard `terraform` binary (no CDKTF CLI)
- **Testing:** Native `terraform test` framework
- **Debugging:** Direct HCL (no translation layer)
- **Community:** Massive Terraform community support

#### **Secrets Management: AWS Secrets Manager + ESO**

**Why This Approach?**
- Uses operator's own AWS account (no external dependencies)
- Native to AWS (no HCP Vault, no HVN, no VPC peering)
- Cost-effective (~$9/month vs ~$300/month for HCP Vault)
- External Secrets Operator provides Kubernetes-native integration
- IRSA-based authentication (no long-lived credentials)

---

## 4. Networking Architecture

### 4.1 Core Principle: One VPC Per Validator Cluster

Each validator deployment creates its own **completely isolated** virtual network, providing maximum isolation and flexibility.

```
Region: us-east-1 (unlimited VPCs supported)

VPC-A: validator-alice-vpc (10.0.0.0/20)
├─ EKS Cluster: validator-alice
├─ NLB: 54.1.1.1 (public IP)
└─ DNS: validator-alice.us-east-1.movementnetwork.xyz → 54.1.1.1

VPC-B: validator-bob-vpc (10.0.0.0/20)  ← SAME CIDR ✅
├─ EKS Cluster: validator-bob
├─ NLB: 54.2.2.2 (public IP)
└─ DNS: validator-bob.us-east-1.movementnetwork.xyz → 54.2.2.2

VPC-C: validator-carol-vpc (10.0.0.0/20)  ← SAME CIDR ✅
├─ EKS Cluster: validator-carol
├─ NLB: 54.3.3.3 (public IP)
└─ DNS: validator-carol.us-east-1.movementnetwork.xyz → 54.3.3.3

Key Point: Private IPs can overlap because VPCs are isolated
```

### 4.2 IP Address Collision is Acceptable

**Private IP ranges CAN overlap** across different validator VPCs:

```
VPC-A (Alice): 10.0.0.0/20
├─ Private IPs: 10.0.1.5, 10.0.1.6, 10.0.1.7
└─ No connectivity to other VPCs

VPC-B (Bob): 10.0.0.0/20  ← SAME as VPC-A ✅
├─ Private IPs: 10.0.1.5, 10.0.1.6, 10.0.1.7  ← SAME ✅
└─ No connectivity to other VPCs

Why this works:
- Each VPC is an isolated network
- No VPC peering between validators
- No Transit Gateway connecting VPCs
- Private IPs only matter within their VPC
- External routing via DNS to unique public IPs
```

**When IP uniqueness WOULD be required:**
- VPC peering between validators (optional future feature)
- Transit Gateway connecting validators (optional)
- VPN tunnels between VPCs (optional)

**Recommendation:** Validators can use the same default CIDR (e.g., `10.0.0.0/20`) without coordination.

### 4.3 DNS-Based External Routing

Each validator has a **unique DNS name** that routes to their VPC's public load balancer:

```
┌──────────────────────────────────────────────────────────────┐
│ DNS Layer (Route53 / Cloudflare)                            │
│                                                              │
│ validator-alice.us-east-1.movementnetwork.xyz               │
│   → A record: 54.1.1.1 (NLB in Alice's VPC)                │
│                                                              │
│ validator-bob.us-east-1.movementnetwork.xyz                 │
│   → A record: 54.2.2.2 (NLB in Bob's VPC)                  │
└──────────────────────────────────────────────────────────────┘
            ↓                    ↓
┌──────────────────┐  ┌──────────────────┐
│ VPC-A (Alice)    │  │ VPC-B (Bob)      │
│ 10.0.0.0/20      │  │ 10.0.0.0/20      │
│                  │  │                  │
│ NLB: 54.1.1.1 ──┐│  │ NLB: 54.2.2.2 ──┐│
│        ↓        ││  │        ↓        ││
│ Validator Pod   ││  │ Validator Pod   ││
│ Private: 10.0.1.5│  │ Private: 10.0.1.5│  ← Same IP OK!
└──────────────────┘  └──────────────────┘

External traffic never crosses VPC boundaries
```

**Traffic Flow:**
1. User queries DNS: `validator-alice.us-east-1.movementnetwork.xyz`
2. DNS returns public IP: `54.1.1.1`
3. User connects to NLB: `54.1.1.1`
4. NLB routes internally (within VPC-A) to: `10.0.1.5`
5. Response flows back through same path

### 4.4 Benefits

| Benefit | Description |
|---------|-------------|
| **Complete Isolation** | Network failure in one VPC doesn't affect others |
| **Independent Lifecycle** | Create/destroy validators without coordination |
| **No CIDR Coordination** | Use same default CIDR for all validators |
| **Simplified Deployment** | No central IP address registry needed |
| **Clear Ownership** | Each validator owns their VPC |
| **Flexible Scaling** | Unlimited validators per region |
| **Security Boundaries** | Network policies can't leak between VPCs |

### 4.5 Multi-Region Support

Same pattern applies globally:

```
us-east-1:
├─ VPC-A: validator-alice (10.0.0.0/20)
├─ VPC-B: validator-bob (10.0.0.0/20)
└─ VPC-C: validator-carol (10.0.0.0/20)

us-west-2:
├─ VPC-D: validator-alice-west (10.0.0.0/20)  ← Can reuse CIDR
├─ VPC-E: validator-bob-west (10.0.0.0/20)

eu-central-1:
├─ VPC-F: validator-eve-eu (10.0.0.0/20)

DNS:
- validator-alice.us-east-1.movementnetwork.xyz → 54.1.1.1
- validator-alice-west.us-west-2.movementnetwork.xyz → 54.10.10.10
- validator-eve-eu.eu-central-1.movementnetwork.xyz → 54.20.20.20
```

---

## 5. Observability Architecture

### 5.1 Problem: Tightly Coupled Observability

**Current Architecture:**
```
Single EKS Cluster
├─ Validator-01 (node group)
├─ Validator-02 (node group)
└─ Observability Stack (node group)
    ├─ Prometheus
    ├─ Loki
    └─ Grafana

❌ Problem: Adding/updating validators affects observability
❌ Problem: Observability changes can disrupt validators
❌ Problem: Cannot scale independently
```

### 5.2 Solution: Decoupled Push-Based Metrics Collection

**New Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│   Observability Cluster (Movement-Operated)             │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ NGINX Ingress (Public NLB)                      │   │
│  │ • https://obs.movementnetwork.xyz               │   │
│  │ • TLS termination                               │   │
│  │                                                 │   │
│  │ Routes:                                         │   │
│  │   /api/v1/write → VictoriaMetrics              │   │
│  │   /loki/api/v1/push → Loki                     │   │
│  └────┬────────────────────────┬───────────────────┘   │
│       ↓                        ↓                        │
│  VictoriaMetrics           Loki                         │
│  (13mo retention)          (30d retention)              │
│                                                         │
│  Grafana (visualization)                                │
└─────────────────────────────────────────────────────────┘
                      ↑
                      │ HTTPS Push
                      │
┌─────────────────────┴─────────────────────┐
│  Validator-Alice (VPC-A)                  │
│  • Validator Pod (built-in metrics push)  │
│  • Fluent Bit DaemonSet (logs)            │
│  Config: PUSH_METRICS_ENDPOINT=...        │
└───────────────────────────────────────────┘
```

### 5.3 Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **VictoriaMetrics** | Metrics storage (13-month retention) | Observability cluster |
| **Loki** | Log aggregation (30-day retention) | Observability cluster |
| **Grafana** | Visualization and dashboards | Observability cluster |
| **NGINX Ingress** | Public HTTPS endpoint | Observability cluster |
| **Fluent Bit** | Log collection | Validator cluster (DaemonSet) |
| **Built-in Metrics** | Push metrics every 15 seconds | Validator pods |

### 5.4 Benefits

| Benefit | Description |
|---------|-------------|
| **Complete Decoupling** | Observability lifecycle independent of validators |
| **Zero Impact Changes** | Add/update validators without affecting monitoring |
| **Public Endpoint** | Validators can push from any network/cloud |
| **Simple Integration** | Just configure endpoint URLs |
| **Cost Efficient** | ~$16/month for NLB only |

### 5.5 Validator Configuration

```bash
# Validators configure these endpoints:
PUSH_METRICS_ENDPOINT="https://obs.movementnetwork.xyz/api/v1/write"
LOKI_ENDPOINT="https://obs.movementnetwork.xyz/loki/api/v1/push"
```

Fluent Bit is automatically deployed as a DaemonSet via Helm chart.

---

## 6. Per Validator Cluster Architecture

### 6.1 Component Structure

```
Per Validator Deployment:
├─ VPC (dedicated, isolated)
│  ├─ Public subnets (2 AZs)
│  ├─ Private subnets (2 AZs)
│  ├─ NAT gateways
│  └─ Security groups
│
├─ EKS Cluster (dedicated)
│  ├─ Control plane
│  ├─ Node group (Bottlerocket)
│  ├─ EBS CSI driver
│  └─ VPC CNI
│
├─ Storage
│  ├─ EBS volumes (io2 6k IOPS)
│  ├─ S3 bucket (blockchain sync)
│  └─ Backup configuration
│
├─ Networking
│  ├─ Network Load Balancer (public)
│  ├─ DNS record (Route53/Cloudflare)
│  └─ TLS certificates (Let's Encrypt)
│
└─ IAM Roles
   ├─ Node role (EC2)
   ├─ Pod roles (IRSA)
   └─ ESO role (Secrets Manager access)
```

### 6.2 Terraform Module Organization

```
terraform-modules/
├── movement-network-base/
│   ├── main.tf
│   ├── vpc.tf
│   ├── security-groups.tf
│   ├── dns.tf
│   └── outputs.tf
│
├── movement-validator-infra/
│   ├── main.tf
│   ├── eks.tf
│   ├── node-group.tf
│   ├── storage.tf
│   ├── iam.tf
│   ├── s3.tf
│   └── outputs.tf
│
└── examples/
    ├── single-validator/
    ├── validator-with-vfn/
    └── full-network/
```

### 6.3 Secrets Management with AWS Secrets Manager

**Architecture:**

```
┌────────────────────────────────────────────────┐
│ AWS Secrets Manager                           │
│  • movement/validator-01/keys                 │
│    - validator_private_key                    │
│    - network_key                              │
│    - consensus_key                            │
└────────────────┬───────────────────────────────┘
                 │
                 │ ESO pulls via IRSA
                 ↓
┌────────────────────────────────────────────────┐
│ Kubernetes (EKS)                              │
│  External Secrets Operator                    │
│    ↓                                          │
│  Kubernetes Secret: validator-keys            │
│    ↓                                          │
│  Validator Pod (mounts secret)                │
└────────────────────────────────────────────────┘
```

**Benefits:**
- ❌ No HCP Vault required
- ❌ No HashiCorp Virtual Networks (HVN)
- ❌ No VPC peering to external services
- ✅ Simple AWS-native solution (~$9/month)
- ✅ IRSA-based authentication
- ✅ Automatic secret rotation

### 6.4 Deployment Workflow

**Community Validator Deployment:**

1. **Clone template repository**
   ```bash
   git clone https://github.com/movementlabs/validator-template my-validator
   cd my-validator
   ```

2. **Configure Terraform**
   ```hcl
   # terraform.tfvars
   validator_name = "alice"
   region         = "us-east-1"
   vpc_cidr       = "10.0.0.0/20"  # Can use default
   ```

3. **Store validator keys**
   ```bash
   aws secretsmanager create-secret \
     --name movement/validator-alice/keys \
     --secret-string file://keys.json
   ```

4. **Deploy infrastructure**
   ```bash
   terraform init
   terraform apply
   ```

5. **Deploy Helm chart**
   ```bash
   helm install validator-alice \
     movement/validator \
     -f values.yaml
   ```

6. **Verify validator**
   ```bash
   kubectl get pods -n validator-alice
   # Validator producing blocks in ~15 minutes
   ```

### 6.5 Resource Requirements

**Per Validator Cluster:**
- **VPC:** 1 VPC with public/private subnets
- **EKS Control Plane:** $73/month
- **Compute:** 1-3 nodes (c6a.4xlarge) ~$500-1500/month
- **Storage:** 500GB io2 @ 6k IOPS ~$95/month
- **NAT Gateway:** $32/month
- **NLB:** $16/month
- **Secrets Manager:** $9/month

**Total:** ~$725-1,725/month per validator (depending on node count)

---

## 7. Migration Path from Current State

### 7.1 Migration Strategy

**Approach:** Launch new validators, then decommission old validators

The migration follows a simple pattern: deploy new validators using the new architecture, validate they're working correctly, then remove the old validators. Since each validator is independent with its own VPC, there's no complex cutover required.

```
Step 1: Build New Infrastructure (Weeks 1-3)
├─ Develop Terraform modules
├─ Develop Helm charts
└─ Test in dev environment

Step 2: Deploy New Validators (Weeks 4-6)
├─ Deploy new validators in each environment
├─ Validate functionality
└─ Monitor for stability

Step 3: Remove Old Validators (Week 7)
├─ Decommission old CDKTF infrastructure
├─ Archive old validator data
└─ Clean up resources
```


### 7.1 Data Migration Options

| Method | Speed | Complexity | Cloud Agnostic |
|--------|-------|------------|----------------|
| **EBS Snapshot** | Fast (~10 min) | Low | No (AWS only) |
| **S3 Sync** | Medium (~1-2 hr) | Low | Yes |
| **P2P Sync** | Slow (~6-12 hr) | Lowest | Yes |

**Recommendation:** EBS snapshots for AWS migrations, S3 sync for cross-cloud

---

## 8. Success Criteria

### 8.1 Functional Success Criteria

| Criterion | Target |
|-----------|--------|
| Deployment Time | < 15 min (infrastructure + validator startup) |
| Validator Independence | 100% (no cross-validator impact) |
| External Adoption | External org successfully deploys |
| Multi-Network Support | 100% (mainnet, testnet, custom) |
| Documentation Coverage | > 90% |

### 8.2 Performance Success Criteria

| Metric | Target |
|--------|--------|
| Block Production Latency | < 1s |
| API Response Time (p99) | < 200ms |
| Memory Usage | < 24GB |
| CPU Usage (avg) | < 60% |

### 8.3 Reliability Success Criteria

| Criterion | Target |
|-----------|--------|
| Uptime SLA | 99.9% (43 min downtime/month) |
| Mean Time to Recovery (MTTR) | < 15 min |
| Successful Deployments | > 95% |
| Failed Deployment Rollback Time | < 5 min |

---

## 9. Timeline and Milestones

### Phase 1: Foundation (Weeks 1-3)

- [ ] Week 1: Design finalization and stakeholder approval
- [ ] Week 1-2: Develop Terraform modules
  - [ ] movement-network-base module
  - [ ] movement-validator-infra module
  - [ ] Terraform unit tests
- [ ] Week 2-3: Develop Helm charts
  - [ ] movement-validator chart
  - [ ] movement-vfn chart
  - [ ] movement-fullnode chart

### Phase 2: Testing (Weeks 4-5)

- [ ] Week 4: Deploy to dev environment
  - [ ] Create test validator cluster
  - [ ] Validate networking isolation
  - [ ] Test secret management
  - [ ] Functional testing
- [ ] Week 5: Shadow deployment in testnet
  - [ ] Deploy alongside existing infrastructure
  - [ ] Performance testing
  - [ ] Load testing
  - [ ] Identify and document issues

### Phase 3: Migration (Weeks 6-9)

- [ ] Week 6: Testnet cutover
  - [ ] Deploy full testnet stack with new modules
  - [ ] Cutover traffic to new infrastructure
  - [ ] Monitor for 7 days
  - [ ] Document lessons learned
- [ ] Week 7-9: Mainnet migration
  - [ ] Week 7: Deploy parallel mainnet infrastructure
  - [ ] Week 8: Gradual traffic migration (25% → 50% → 75%)
  - [ ] Week 9: Full cutover and decommission old infrastructure

### Phase 4: Public Release (Week 10)

- [ ] Week 10: Documentation and announcement
  - [ ] Complete external documentation
  - [ ] Create deployment examples
  - [ ] Public announcement
  - [ ] Community validator onboarding

---

## 10. Appendix

### 10.1 Glossary

- **CDKTF:** Cloud Development Kit for Terraform (TypeScript → Terraform)
- **CIDR:** Classless Inter-Domain Routing (IP address allocation)
- **EBS:** Elastic Block Store (AWS block storage)
- **EKS:** Elastic Kubernetes Service (AWS managed Kubernetes)
- **ESO:** External Secrets Operator (Kubernetes secrets management)
- **HVN:** HashiCorp Virtual Network (HCP networking)
- **IRSA:** IAM Roles for Service Accounts (Kubernetes + AWS IAM)
- **NLB:** Network Load Balancer (AWS Layer 4 load balancer)
- **VFN:** Validator Full Node
- **VPC:** Virtual Private Cloud (AWS isolated network)

### 10.2 References

#### **Terraform Documentation**
- [Terraform 1.9 Release Notes](https://www.terraform.io/docs/v1.9.x)
- [Terraform Module Best Practices](https://www.terraform.io/docs/modules/index.html)
- [Terraform Testing Framework](https://www.terraform.io/docs/language/tests/index.html)

#### **Kubernetes and Helm**
- [Helm 3.16 Documentation](https://helm.sh/docs/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [External Secrets Operator](https://external-secrets.io/)

#### **AWS Documentation**
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [VPC Design Guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)

#### **Movement Network**
- [Movement Network GitHub](https://github.com/movementlabsxyz)
- [Movement Network Documentation](https://docs.movementnetwork.xyz)

### 10.3 Comparison with Current State

| Aspect | Current (CDKTF) | New Design (Terraform HCL) |
|--------|-----------------|----------------------------|
| **Lines of Code** | ~4,000 lines (TypeScript) | ~1,500 lines (HCL) |
| **Dependencies** | Node.js, npm, CDKTF, TypeScript | Terraform binary only |
| **Learning Curve** | High (3 technologies) | Low (Terraform only) |
| **External Adoption** | Not possible | Fully supported |
| **Validator Isolation** | Shared VPC | One VPC per validator |
| **IP Coordination** | Required | Not required |
| **Secret Management** | 1Password (internal) | AWS Secrets Manager (user's) |
| **Observability Coupling** | Tightly coupled | Decoupled |
| **Deployment Time** | 30-45 min | < 15 min |
| **Cost per Validator** | ~$1,000/month | ~$725-1,725/month |
| **Testing** | Manual only | Automated with Terraform tests |

### 10.4 FAQ

**Q: Can I use a different cloud provider (GCP, Azure)?**
A: The networking and EKS modules are AWS-specific, but the Helm charts are cloud-agnostic. For GCP/Azure, you would need to create equivalent networking modules, but can reuse the Helm charts.

**Q: Do I need to coordinate IP addresses with other validators?**
A: No. Each validator has its own VPC, so IP addresses can overlap without conflict. Only coordinate if you plan to connect VPCs via peering.

**Q: How do I handle validator key rotation?**
A: Update the secret in AWS Secrets Manager, and ESO will automatically sync the new secret to Kubernetes. The validator pod will need to be restarted to use the new key.

**Q: Can I run multiple validators in the same VPC?**
A: While technically possible, the design recommends one VPC per validator for maximum isolation and operational simplicity.

**Q: What's the minimum cost to run a validator?**
A: Approximately $725/month with single-node configuration (EKS control plane + 1 c6a.4xlarge node + storage + networking).

**Q: How do I migrate from the current CDKTF infrastructure?**
A: Follow the phased migration approach (Section 7): deploy new infrastructure in parallel, sync data, validate, then cutover traffic.

**Q: Do I need HCP Vault for production validators?**
A: No. AWS Secrets Manager is sufficient for most use cases. HCP Vault is only needed for advanced cryptographic operations like signing without exposing keys.

---

## Document Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| **Author** | Infrastructure Team | | |
| **Technical Reviewer** | | | |
| **Architecture Reviewer** | | | |
| **Security Reviewer** | | | |
| **Product Owner** | | | |

---

**Document Status:** Ready for Review
**Next Steps:** Architecture review meeting, stakeholder approval, implementation planning

**Version History:**
- v2.1 (2026-01-30): Restructured with clear sections for requirements, problems, architecture
- v2.0 (2026-01-23): Initial comprehensive redesign proposal
- v1.0 (2025-12-15): Original CDKTF architecture documentation
