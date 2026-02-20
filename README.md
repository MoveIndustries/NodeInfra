# Movement Network Validator Infrastructure

Production-ready infrastructure automation for deploying Movement Network validators on AWS EKS with Terraform and Kubernetes.

## What's in This Repo

This repository provides:

- **Terraform Modules** - Reusable infrastructure components for AWS (VPC, EKS, IAM)
- **Unified Helm Chart** - Single `movement-node` chart for deploying validators, VFNs, and fullnodes
- **Deployment Tools** - Python automation for orchestrating Terraform + Helm deployments
- **Integration Tests** - End-to-end validation of complete deployments
- **Examples** - Ready-to-use deployment configurations

### Repository Structure

```
NodeInfra/
├── terraform-modules/
│   ├── movement-network-base/      # VPC, subnets, security groups, DNS
│   └── movement-validator-infra/   # EKS cluster, node groups, IAM, storage
│
├── charts/
│   └── movement-node/              # Unified Helm chart for validator/VFN/fullnode
│
├── examples/
│   ├── public-fullnode/            # Single fullnode deployment
│   └── validator-vfn/              # 3-tier: validator + VFN + fullnode
│
├── tools/                          # Python deployment automation
│   ├── terraform.py               # Terraform operations
│   ├── eks.py                     # EKS cluster management
│   ├── helm.py                    # Helm chart deployment
│   ├── validation.py              # Kubernetes health checks
│   └── cluster.py                 # Complete orchestration
│
└── tests/integration/
    ├── test_public_fullnode.py    # Single fullnode test
    └── test_validator_vfn.py      # 3-tier deployment test
```

## Quick Start: Run Integration Test

### Prerequisites

1. **AWS Credentials** - Configured with permissions to create VPC, EKS, EC2, IAM, Secrets Manager
2. **AWS CLI** - `aws configure` with profile or default credentials
3. **kubectl** - Kubernetes CLI tool
4. **Terraform** - v1.9.0 or higher
5. **Helm** - v3.0 or higher
6. **Poetry** - Python dependency management
7. **Python 3.10+**

Install tools on macOS:
```bash
brew install awscli kubectl terraform helm poetry
```

### Step-by-Step: Deploy 3-Tier Validator Network

This guide walks through running `tests/integration/test_validator_vfn.py`, which deploys:
- **Validator** (private, ClusterIP)
- **VFN** (private, ClusterIP, connects to validator)
- **Fullnode** (public, LoadBalancer, connects to VFN)

#### Step 1: Generate Validator Keys

First, generate validator identity keys (one-time setup):

```bash
# Install Aptos CLI if not already installed
# See: https://aptos.dev/tools/aptos-cli/install-cli/

# Generate validator keys
aptos genesis generate-keys --output-dir ./validator-keys

# This creates:
# - validator-keys/validator-identity.yaml
# - validator-keys/validator-full-node-identity.yaml
```

#### Step 2: Store Keys in AWS Secrets Manager

Store the validator identity in AWS Secrets Manager:

```bash
# Set your AWS profile
export AWS_PROFILE=mi:scratchpad  # Or your profile name
export AWS_REGION=us-east-1

# Create secret with validator identity
aws secretsmanager create-secret \
  --name movement/testnet-vn-02/validator-identity \
  --description "Movement validator identity for testnet-vn-02" \
  --secret-string file://validator-keys/validator-identity.yaml \
  --region us-east-1

# Verify secret was created
aws secretsmanager describe-secret \
  --secret-id movement/testnet-vn-02/validator-identity \
  --region us-east-1
```

#### Step 3: Create .env Configuration

Create configuration file for the validator-vfn example:

```bash
cd examples/validator-vfn

# Copy the example template
cp .env.example .env

# Edit .env with your values
```

**Required .env contents:**

```bash
# AWS Configuration
AWS_PROFILE=mi:scratchpad           # Your AWS profile name
AWS_REGION=us-east-1                # AWS region

# Validator Configuration
VALIDATOR_NAME=testnet-vn-02        # Unique validator name
VALIDATOR_KEYS_SECRET_NAME=movement/testnet-vn-02/validator-identity  # AWS Secrets Manager secret name

# VFN Configuration
DEPLOY_VFN=true                     # Enable VFN deployment
VFN_NAME=vfn-01                     # VFN service name

# Fullnode Configuration
DEPLOY_FULLNODE=true                # Enable fullnode deployment
FULLNODE_NAME=fullnode-01           # Fullnode service name

# Network Configuration
NETWORK_NAME=testnet                # Movement network name
CHAIN_ID=250                        # Chain ID

# Infrastructure Configuration
VPC_CIDR=10.0.0.0/20               # VPC CIDR block
NODE_INSTANCE_TYPES=m5.2xlarge,m6i.2xlarge  # EC2 instance types (comma-separated)

# Optional: DNS Configuration (if you want public DNS)
ENABLE_DNS=false                    # Set to true if you have Route53 hosted zone
# DNS_ZONE_NAME=movementnetwork.xyz # Your DNS zone name
```

**Save the file** and return to the repository root:

```bash
cd ../..  # Back to repository root
```

#### Step 4: Install Python Dependencies

Install the required Python dependencies (kubernetes, boto3):

```bash
# Install runtime dependencies
poetry install --no-root
```

**Note:** The `tools/` package is used directly from the filesystem (not installed). The test files use `sys.path.insert()` to import from the `tools/` directory. The `poetry install` command only installs the external dependencies (kubernetes, boto3) declared in `pyproject.toml`.

#### Step 5: Run the Integration Test

Run the complete 3-tier deployment test:

```bash
# Run integration test
poetry run python tests/integration/test_validator_vfn.py
```

**What the test does:**

1. ✅ Provisions AWS infrastructure (VPC, EKS, IAM roles) via Terraform
2. ✅ Configures kubectl to access the EKS cluster
3. ✅ Creates Kubernetes namespace
4. ✅ Reads validator keys from AWS Secrets Manager
5. ✅ Creates Kubernetes secret from AWS secret
6. ✅ Deploys validator pod (ClusterIP service)
7. ✅ Deploys VFN pod (ClusterIP service, connects to validator)
8. ✅ Deploys fullnode pod (LoadBalancer service, connects to VFN)
9. ✅ Waits for all pods to become ready
10. ✅ Validates fullnode API is healthy via LoadBalancer
11. ✅ Verifies correct service types (only fullnode is public)

**Expected output:**

```
[INFO] Validator-VFN-Fullnode integration test (3-tier topology)
[INFO] Using deployment script: examples/validator-vfn/deploy.py
[INFO] Using unified Helm chart: charts/movement-node
[INFO] Test configuration:
[INFO]   Validator: testnet-vn-02 (ClusterIP) - node.type=validator
[INFO]   VFN: vfn-01 (ClusterIP) - node.type=vfn
[INFO]   Fullnode: fullnode-01 (LoadBalancer) - node.type=fullnode
[INFO]   Chart: charts/movement-node (unified chart for all)
[INFO]   Secret: AWS Secrets Manager (movement/testnet-vn-02/validator-identity)

... (deployment logs) ...

[SUCCESS] ✅ Validator service 'testnet-vn-02' is ClusterIP (private)
[SUCCESS] ✅ VFN service 'vfn-01' is ClusterIP (private)
[SUCCESS] ✅ Fullnode service 'fullnode-01' is LoadBalancer (public)
[SUCCESS] ✅ LoadBalancer hostname: a1234567890.us-east-1.elb.amazonaws.com
[SUCCESS] 🎉 Integration test passed!
```

#### Step 6: Access Your Deployed Network

After successful deployment, access the fullnode API:

```bash
# Get the LoadBalancer hostname
export FULLNODE_LB=$(kubectl get svc fullnode-01 -n movement-l1 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Query the API
curl http://${FULLNODE_LB}:8080/v1

# Expected response:
# {
#   "chain_id": 250,
#   "ledger_version": "12345678",
#   "ledger_timestamp": "1234567890",
#   ...
# }
```

#### Step 7: Cleanup

Destroy the infrastructure when done:

```bash
cd examples/validator-vfn

# Run destroy via deployment script
python deploy.py --destroy

# Or manually with Terraform
terraform destroy -auto-approve

# Delete the secret from AWS Secrets Manager (optional)
aws secretsmanager delete-secret \
  --secret-id movement/testnet-vn-02/validator-identity \
  --force-delete-without-recovery \
  --region us-east-1
```

## Development

### Code Quality & Linting

This repository enforces code quality for both Python and Terraform using pre-commit hooks.

**Setup (one-time):**

```bash
# Install all linting tools and pre-commit hooks
make install-tools
```

**Manual Commands:**

```bash
# Format all code (Python + Terraform)
make fmt

# Run all linting checks (Python + Terraform)
make lint

# Python-specific
make py-fmt          # Format with Black + isort
make py-lint         # Lint with Ruff
make py-type-check   # Type check with mypy

# Terraform-specific
make tflint          # Lint Terraform files
make validate        # Validate Terraform syntax
```

**Automatic on Commit:**

Pre-commit hooks run automatically on `git commit`:
- ✅ Black (Python formatter)
- ✅ isort (Python import sorting)
- ✅ Ruff (Python linter)
- ✅ mypy (Python type checker)
- ✅ Terraform fmt
- ✅ Terraform validate
- ✅ General checks (trailing whitespace, YAML syntax, etc.)

**Manually run pre-commit:**

```bash
poetry run pre-commit run --all-files
```

### Running Tests Manually

**Public Fullnode Test:**

```bash
# Single fullnode with S3 bootstrap
poetry run python tests/integration/test_public_fullnode.py
```

**3-Tier Validator Test:**

```bash
# Validator + VFN + Fullnode
poetry run python tests/integration/test_validator_vfn.py
```

## Architecture

### Network Topology: 3-Tier Deployment

```
┌─────────────────────────────────────────────────────┐
│  VPC (10.0.0.0/20)                                  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  EKS Cluster: testnet-vn-02                  │  │
│  │                                               │  │
│  │  ┌──────────────┐  Private Network          │  │
│  │  │  Validator   │◄──────────┐               │  │
│  │  │ (ClusterIP)  │           │               │  │
│  │  └──────────────┘           │               │  │
│  │                              │               │  │
│  │                         ┌────▼────┐          │  │
│  │                         │   VFN   │          │  │
│  │                         │(ClusterIP)         │  │
│  │                         └────┬────┘          │  │
│  │                              │               │  │
│  │                         ┌────▼────┐          │  │
│  │                         │Fullnode │          │  │
│  │                         │  (LB)   │          │  │
│  │                         └────┬────┘          │  │
│  └──────────────────────────────┼───────────────┘  │
│                                 │                  │
│  ┌──────────────────────────────▼───────────────┐  │
│  │  Network Load Balancer (Public)              │  │
│  │  Port 8080 (API), Port 6182 (P2P)            │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Unified Helm Chart

The `charts/movement-node` chart deploys all three node types using the same template with different `node.type` values:

- **`node.type=validator`** - Deploys validator with private key from secret
- **`node.type=vfn`** - Deploys VFN that connects to validator
- **`node.type=fullnode`** - Deploys fullnode that connects to VFN

This unified approach:
- ✅ Reduces duplication
- ✅ Ensures consistency across node types
- ✅ Simplifies maintenance
- ✅ Enables easy configuration

## Deployment Tools

The `tools/` package provides reusable Python modules for infrastructure automation:

- **`terraform.py`** - TerraformManager for Terraform operations
- **`eks.py`** - EKSManager for cluster management and kubeconfig
- **`helm.py`** - HelmManager for Helm chart deployments
- **`validation.py`** - Pod and API health validation
- **`cluster.py`** - ClusterManager orchestrates complete deployments
- **`cli.py`** - Command-line interface utilities
- **`utils.py`** - Logging, command execution, environment loading

### Example: Using ClusterManager

```python
from pathlib import Path
from tools import ClusterManager

# Initialize
cluster = ClusterManager(
    terraform_dir=Path("examples/validator-vfn"),
    chart_dir=Path("charts/movement-node"),
    root_dir=Path("."),
)

# Deploy infrastructure + workload
cluster.deploy(
    env_vars={"AWS_PROFILE": "mi:scratchpad"},
    terraform_vars={"validator_name": "testnet-vn-02"},
    helm_config={
        "namespace": "movement-l1",
        "release_name": "testnet-vn-02",
        "set_values": {"node.type": "validator"},
    },
    validate=True,  # Wait for pods to be ready + API healthy
)

# Destroy everything
cluster.destroy(terraform_vars={"validator_name": "testnet-vn-02"})
```

## AWS Costs

**3-Tier Deployment (Validator + VFN + Fullnode):**

| Resource | Estimated Cost |
|----------|----------------|
| EKS Control Plane | ~$73/month |
| EC2 Instances (3x m5.2xlarge on-demand) | ~$900/month |
| NAT Gateway (2x HA) | ~$64/month |
| Network Load Balancer | ~$16/month |
| EBS Storage (1.5TB gp3) | ~$120/month |
| **Total** | **~$1,173/month** |

**Cost Optimization:**
- Use spot instances: **70% savings** (~$350/month instead of $900)
- Single NAT gateway: **$32/month savings**
- Smaller instance types for dev/test
- Destroy resources when not in use

## Troubleshooting

### Secret Not Found

```
Error: Secret not found in AWS Secrets Manager
```

**Solution:** Verify secret exists and has correct name:

```bash
aws secretsmanager describe-secret \
  --secret-id movement/testnet-vn-02/validator-identity \
  --region us-east-1
```

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n movement-l1

# View pod logs
kubectl logs -n movement-l1 testnet-vn-02-0

# Describe pod for events
kubectl describe pod -n movement-l1 testnet-vn-02-0
```

### Terraform State Lock

```
Error acquiring the state lock
```

**Solution:** Release the lock or use different backend:

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### kubectl Not Configured

```
Error: Unable to connect to cluster
```

**Solution:** Update kubeconfig:

```bash
aws eks update-kubeconfig \
  --name testnet-vn-02-cluster \
  --region us-east-1 \
  --profile mi:scratchpad
```

## Documentation

- **[MILESTONE_PLAN.md](MILESTONE_PLAN.md)** - Complete project roadmap and architecture
- **[examples/validator-vfn/README.md](examples/validator-vfn/README.md)** - 3-tier deployment guide
- **[examples/public-fullnode/README.md](examples/public-fullnode/README.md)** - Fullnode deployment guide
- **[tools/README.md](tools/README.md)** - Python tools documentation
- **[charts/movement-node/README.md](charts/movement-node/README.md)** - Helm chart documentation

## Support

For issues, questions, or contributions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review existing [GitHub Issues](../../issues)
3. Create a new issue with:
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs and error messages
   - Environment details (AWS region, Terraform version, etc.)

## License

[Add your license here]

---

**Quick Links:**
- [Run Integration Test](#quick-start-run-integration-test)
- [Development Setup](#development)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)
