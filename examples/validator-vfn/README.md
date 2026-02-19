# Validator + VFN Deployment Example

This example demonstrates how to deploy a complete Movement Network validator setup consisting of:
- **Validator (VN)**: The core validator node that participates in consensus
- **Validator Full Node (VFN)**: A full node that syncs from the validator and exposes public API

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/20)                    │
│                                                         │
│  ┌────────────────────────────────────────────────┐   │
│  │            EKS Cluster: validator-01            │   │
│  │                                                 │   │
│  │  ┌──────────────┐    Private VFN Network      │   │
│  │  │ Validator    │◄──────────────────┐         │   │
│  │  │   (VN)       │      Port 6181     │         │   │
│  │  │              │                     │         │   │
│  │  │ • Produces   │                     │         │   │
│  │  │   blocks     │                     │         │   │
│  │  │ • No public  │                  ┌──▼─────┐  │   │
│  │  │   access     │                  │  VFN   │  │   │
│  │  └──────────────┘                  │        │  │   │
│  │                                    │ • Syncs│  │   │
│  │                                    │   from │  │   │
│  │                                    │   VN   │  │   │
│  │                                    │ • Public│  │   │
│  │                                    │   API  │  │   │
│  │                                    └───┬────┘  │   │
│  │                                        │       │   │
│  │                                        │       │   │
│  └────────────────────────────────────────┼───────┘   │
│                          ▲                 │           │
│                          │                 │           │
│  ┌───────────────────────┴─────────────────▼───────┐  │
│  │    Network Load Balancer (Public)              │  │
│  │    • Port 8080 (API)                           │  │
│  │    • Port 6182 (P2P - Public Fullnode)        │  │
│  └────────────────────────────────────────────────┘  │
│                          ▲                             │
└──────────────────────────┼─────────────────────────────┘
                           │
               ┌───────────┴──────────┐
               │   Route53 DNS        │
               │                      │
               │ validator-01.       │
               │ us-east-1.          │
               │ movementnetwork.xyz  │
               └──────────────────────┘
```

## Prerequisites

1. **AWS Credentials**: Configure AWS CLI with appropriate credentials
2. **Terraform**: Version 1.9 or higher
3. **kubectl**: For Kubernetes cluster management
4. **Helm**: Version 3.x for chart deployment
5. **Validator Keys**: Generated validator identity keys

## Step 1: Generate Validator Keys

Before deploying, you need to generate validator identity keys using the Aptos CLI or Movement CLI.

```bash
# Using Aptos CLI
aptos genesis generate-keys --output-dir ./keys

# This will generate files like:
# - validator-identity.yaml
# - validator-full-node-identity.yaml
```

The `validator-identity.yaml` should contain:
```yaml
---
account_address: "0x..."
account_private_key: "0x..."
consensus_private_key: "0x..."
network_private_key: "0x..."
```

## Step 2: Store Keys in AWS Secrets Manager (Recommended)

**NEW**: Terraform can now automatically create Kubernetes secrets from AWS Secrets Manager.

```bash
# Store validator identity in AWS Secrets Manager
aws secretsmanager create-secret \
  --name movement/validator-01/validator-identity \
  --secret-string file://keys/validator-identity.yaml \
  --description "Validator identity for validator-01"

# Verify the secret was created
aws secretsmanager describe-secret \
  --secret-id movement/validator-01/validator-identity
```

### Alternative: Manual Kubernetes Secret Creation

If you prefer not to use AWS Secrets Manager, you can create the Kubernetes secret manually:

```bash
# Create namespace and secret manually
kubectl create namespace movement-l1
kubectl create secret generic validator-identity \
  --from-file=validator-identity.yaml=./keys/validator-identity.yaml \
  -n movement-l1
```

**Note**: If using the manual approach, leave `VALIDATOR_KEYS_SECRET_NAME` empty in your `.env` file.

## Step 3: Configure Deployment

Copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
cp .env.example .env
```

Edit `terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "us-east-1"
aws_profile = "default"

# Validator Configuration
validator_name = "validator-01"
network_name = "testnet"

# VPC Configuration
vpc_cidr = "10.0.0.0/20"

# DNS Configuration (optional)
enable_dns = true
dns_zone_name = "movementnetwork.xyz"
dns_provider = "route53"

# Node Configuration
node_instance_types = ["c6a.4xlarge"]
node_desired_size = 2  # One for validator, one for VFN

# VFN Configuration
vfn_key = "b0f405a3e75516763c43a2ae1d70423699f34cd68fa9f8c6bb2d67aa87d0af69"
vfn_peer_id = "00000000000000000000000000000000d58bc7bb154b38039bc9096ce04e1237"
```

Edit `.env`:

```bash
# AWS Configuration
AWS_PROFILE=default
AWS_REGION=us-east-1

# Validator Configuration
VALIDATOR_NAME=validator-01
NETWORK_NAME=testnet

# VFN Configuration
VFN_KEY=b0f405a3e75516763c43a2ae1d70423699f34cd68fa9f8c6bb2d67aa87d0af69
VFN_PEER_ID=00000000000000000000000000000000d58bc7bb154b38039bc9096ce04e1237
```

## Step 4: Deploy Infrastructure

Deploy using the automation script:

```bash
# Deploy infrastructure and both validator + VFN
python3 deploy.py

# Or deploy with validation
python3 deploy.py --validate

# Destroy when done
python3 deploy.py --destroy
```

Or deploy manually:

```bash
# 1. Deploy Terraform infrastructure
terraform init
terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name validator-01-cluster --region us-east-1

# 3. Deploy validator chart
helm upgrade --install validator-01 ../../charts/movement-validator \
  --namespace movement-l1 \
  --create-namespace \
  --values validator-values.yaml

# 4. Deploy VFN chart
helm upgrade --install vfn-01 ../../charts/movement-vfn \
  --namespace movement-l1 \
  --values vfn-values.yaml
```

## Step 5: Verify Deployment

Check the status of your deployment:

```bash
# Check pods
kubectl get pods -n movement-l1

# Expected output:
# NAME            READY   STATUS    RESTARTS   AGE
# validator-01-0  1/1     Running   0          5m
# vfn-01-0        1/1     Running   0          5m

# Check validator logs
kubectl logs -n movement-l1 validator-01-0 --tail=100

# Check VFN logs
kubectl logs -n movement-l1 vfn-01-0 --tail=100

# Check validator API
kubectl exec -n movement-l1 validator-01-0 -- curl -s localhost:8080/v1 | jq .

# Check VFN API (via load balancer)
VFN_URL=$(terraform output -raw vfn_url)
curl -s $VFN_URL/v1 | jq .
```

## Step 6: Monitor Sync Status

Monitor the sync status of both nodes:

```bash
# Watch validator block height
watch "kubectl exec -n movement-l1 validator-01-0 -- curl -s localhost:8080/v1 | jq -r '.ledger_version'"

# Watch VFN block height
watch "kubectl exec -n movement-l1 vfn-01-0 -- curl -s localhost:8080/v1 | jq -r '.ledger_version'"

# VFN should be within 10 blocks of validator
```

## Configuration Details

### Validator Configuration

The validator is configured with:
- **Role**: Validator (produces blocks)
- **Consensus**: Participates in consensus
- **API**: Private (ClusterIP only)
- **VFN Port**: 6181 (private network to VFN)
- **Validator Port**: 6180 (validator network)

### VFN Configuration

The VFN is configured with:
- **Role**: Full Node (syncs from validator)
- **Upstream**: Connects to validator on port 6181
- **API**: Public (via LoadBalancer)
- **Public P2P**: Port 6182 (for other full nodes)

## Network Topology

### Private VFN Network
- **Port**: 6181
- **Protocol**: TCP (noise-ik handshake)
- **Purpose**: Validator → VFN data sync
- **Access**: Private (within cluster)

### Public Full Node Network
- **Port**: 6182
- **Protocol**: TCP
- **Purpose**: VFN → External full nodes
- **Access**: Public (via LoadBalancer)

## Security Considerations

1. **Validator Isolation**: The validator has no public endpoints
2. **Secret Management**: Validator keys stored in Kubernetes secrets
3. **Network Segmentation**: Validator and VFN use separate network identities
4. **TLS/mTLS**: Communication uses noise protocol encryption

## Troubleshooting

### Validator Not Producing Blocks

```bash
# Check validator logs
kubectl logs -n movement-l1 validator-01-0 | grep -i error

# Check consensus status
kubectl exec -n movement-l1 validator-01-0 -- curl -s localhost:9102/metrics | grep consensus

# Verify identity is correct
kubectl exec -n movement-l1 validator-01-0 -- cat /opt/data/genesis/validator-identity.yaml
```

### VFN Not Syncing

```bash
# Check VFN logs
kubectl logs -n movement-l1 vfn-01-0 | grep -i "sync\|error"

# Verify connection to validator
kubectl exec -n movement-l1 vfn-01-0 -- curl -s localhost:9102/metrics | grep network_peers

# Check VFN configuration
kubectl exec -n movement-l1 vfn-01-0 -- cat /etc/vfn/vfn.yaml
```

### Slow Sync

If initial sync is slow, the VFN is downloading the entire blockchain from the validator. This is expected and can take several hours depending on the chain length.

## Cost Estimation

Monthly AWS costs (us-east-1):

| Resource | Cost |
|----------|------|
| EKS Control Plane | ~$73 |
| 2x c6a.4xlarge nodes | ~$1,000 |
| EBS Storage (1TB) | ~$100 |
| Network Load Balancer | ~$16 |
| Data Transfer | Variable |
| **Total** | **~$1,189/month** |

## Cleanup

To destroy all resources:

```bash
# Using automation
python3 deploy.py --destroy

# Or manually
helm uninstall validator-01 -n movement-l1
helm uninstall vfn-01 -n movement-l1
terraform destroy
```

## Next Steps

1. **Add Monitoring**: Deploy Prometheus/Grafana for metrics
2. **Add Full Nodes**: Deploy additional full nodes that sync from VFN
3. **Setup Alerts**: Configure alerting for validator downtime
4. **Backup Strategy**: Implement automated backups of validator data

## References

- [Movement Network Documentation](https://docs.movementlabs.xyz)
- [Aptos Node Documentation](https://aptos.dev/nodes)
- [MILESTONE_PLAN.md](../../MILESTONE_PLAN.md) - Project roadmap