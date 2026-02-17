# Movement Node Helm Chart

A unified Helm chart for deploying Movement Network nodes. This chart can deploy:
- **Validator (VN)**: Core validator node that participates in consensus
- **Validator Full Node (VFN)**: Full node that syncs from validator and exposes public API
- **Full Node (FN)**: Public full node that syncs from VFN or other seeds

## Features

- ✅ **Single Chart**: One chart for all node types
- ✅ **Type Selection**: Simple `node.type` parameter to choose node type
- ✅ **Auto-Configuration**: Service type and networking auto-configured per node type
- ✅ **Genesis Support**: Automatic genesis file download
- ✅ **S3 Bootstrap**: Optional S3 restore for fullnodes
- ✅ **Flexible Networking**: Supports validator↔VFN private network and public P2P

## Quick Start

### Deploy a Validator

```bash
helm install validator-01 ./charts/movement-node \
  --set node.type=validator \
  --set node.name=validator-01 \
  --set validator.identity.existingSecret=validator-identity \
  --namespace movement-l1 \
  --create-namespace
```

### Deploy a VFN

```bash
helm install vfn-01 ./charts/movement-node \
  --set node.type=vfn \
  --set node.name=vfn-01 \
  --set vfn.validator.serviceName=validator-01 \
  --set vfn.validator.namespace=movement-l1 \
  --namespace movement-l1
```

### Deploy a Full Node

```bash
helm install fullnode-01 ./charts/movement-node \
  --set node.type=fullnode \
  --set node.name=fullnode-01 \
  --namespace movement-l1
```

## Node Type Configurations

### Validator Configuration

**Purpose**: Participates in consensus and produces blocks

**Key Settings**:
```yaml
node:
  type: "validator"
  name: "validator-01"

validator:
  identity:
    existingSecret: "validator-identity"  # Required
  vfn:
    enabled: true
    key: "..."      # VFN public key
    peerId: "..."   # VFN peer ID

service:
  type: ""  # Auto-set to ClusterIP (private)
```

**Networking**:
- Port 6180: Validator network (with other validators)
- Port 6181: Private VFN network (to VFN only)
- Port 8080: API (ClusterIP only, not public)
- No LoadBalancer - completely private

**Storage**: Requires persistent storage for blockchain data

### VFN Configuration

**Purpose**: Syncs from validator, provides public API and P2P

**Key Settings**:
```yaml
node:
  type: "vfn"
  name: "vfn-01"

vfn:
  validator:
    serviceName: "validator-01"  # Upstream validator
    namespace: "movement-l1"
    peerId: "..."
    port: 6181
  fullnode:
    enabled: true
    publicKey: "..."  # Public fullnode identity
    peerId: "..."

service:
  type: ""  # Auto-set to LoadBalancer
```

**Networking**:
- Port 6181: Connects to validator (private)
- Port 6182: Public P2P (for fullnodes)
- Port 8080: Public API (via LoadBalancer)
- LoadBalancer enabled automatically

**Storage**: Requires persistent storage for blockchain data

### Full Node Configuration

**Purpose**: Public node that syncs from VFN or seeds

**Key Settings**:
```yaml
node:
  type: "fullnode"
  name: "fullnode-01"

fullnode:
  seeds:
    - peerId: "..."
      addresses:
        - "/dns/vfn-01.../tcp/6182/..."

bootstrap:
  enabled: true  # Optional: restore from S3
  s3:
    bucket: "my-bucket"
    prefix: "testnet/db"

service:
  type: ""  # Auto-set to LoadBalancer
```

**Networking**:
- Port 6182: Connects to seeds (VFN or other fullnodes)
- Port 8080: Public API (via LoadBalancer)
- LoadBalancer enabled automatically

**Storage**: Requires persistent storage for blockchain data

## Complete Example: Validator + VFN

### Step 1: Create Validator Secret

```bash
kubectl create namespace movement-l1
kubectl create secret generic validator-identity \
  --from-file=validator-identity.yaml=./keys/validator-identity.yaml \
  -n movement-l1
```

### Step 2: Create Values Files

**validator-values.yaml**:
```yaml
node:
  type: validator
  name: validator-01

validator:
  identity:
    existingSecret: validator-identity
  vfn:
    enabled: true
    key: "b0f405a3e75516763c43a2ae1d70423699f34cd68fa9f8c6bb2d67aa87d0af69"
    peerId: "00000000000000000000000000000000d58bc7bb154b38039bc9096ce04e1237"

network:
  name: testnet

resources:
  requests:
    cpu: "12"
    memory: "24Gi"
  limits:
    cpu: "14"
    memory: "28Gi"

storage:
  size: "500Gi"
  storageClassName: "gp3"
```

**vfn-values.yaml**:
```yaml
node:
  type: vfn
  name: vfn-01

vfn:
  validator:
    serviceName: validator-01
    namespace: movement-l1
    peerId: "00000000000000000000000000000000d58bc7bb154b38039bc9096ce04e1237"
    port: 6181
  fullnode:
    enabled: true
    publicKey: "18FD979E14162B541B874490D47BD26BC94A398429337C536C48F5E9C8708D7B"
    peerId: "9967ebf40ac8c2ccb38709488952da1826176584ea3067b63b1695362ecb3d1f"

network:
  name: testnet

resources:
  requests:
    cpu: "12"
    memory: "24Gi"

storage:
  size: "500Gi"
  storageClassName: "gp3"

loadBalancer:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

### Step 3: Deploy Both Nodes

```bash
# Deploy validator first
helm install validator-01 ./charts/movement-node \
  -f validator-values.yaml \
  -n movement-l1

# Wait for validator to be ready
kubectl wait --for=condition=Ready pod/validator-01-0 -n movement-l1 --timeout=600s

# Deploy VFN
helm install vfn-01 ./charts/movement-node \
  -f vfn-values.yaml \
  -n movement-l1

# Wait for VFN to be ready
kubectl wait --for=condition=Ready pod/vfn-01-0 -n movement-l1 --timeout=600s
```

### Step 4: Verify

```bash
# Check validator API (internal)
kubectl exec -n movement-l1 validator-01-0 -- curl -s localhost:8080/v1 | jq .

# Check VFN API (via LoadBalancer)
VFN_URL=$(kubectl get svc -n movement-l1 vfn-01 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$VFN_URL:8080/v1 | jq .

# Verify VFN is syncing from validator
kubectl logs -n movement-l1 vfn-01-0 | grep -i "sync\|connected"
```

## Service Type Auto-Configuration

The chart automatically configures service types based on node type:

| Node Type | Service Type | Public Access | LoadBalancer |
|-----------|--------------|---------------|--------------|
| validator | ClusterIP | ❌ No | ❌ No |
| vfn | LoadBalancer | ✅ Yes | ✅ Yes |
| fullnode | LoadBalancer | ✅ Yes | ✅ Yes |

Override by explicitly setting `service.type`:
```yaml
service:
  type: "LoadBalancer"  # Force LoadBalancer for any node type
```

## Port Mapping

| Port | Purpose | Validator | VFN | Full Node |
|------|---------|-----------|-----|-----------|
| 8080 | API | ✅ Private | ✅ Public | ✅ Public |
| 9101 | Metrics | ✅ | ✅ | ✅ |
| 9102 | Admin | ✅ | ✅ | ✅ |
| 6180 | Validator Network | ✅ | ❌ | ❌ |
| 6181 | Private VFN Network | ✅ | ✅ | ❌ |
| 6182 | Public P2P | ❌ | ✅ | ✅ |

## Storage Configuration

All node types require persistent storage:

```yaml
storage:
  size: "500Gi"
  storageClassName: "gp3"
  iops: 6000          # For AWS gp3
  throughput: 500     # For AWS gp3
```

### S3 Bootstrap (Full Nodes Only)

For faster fullnode deployment, enable S3 bootstrap:

```yaml
bootstrap:
  enabled: true
  s3:
    bucket: "movement-backup"
    prefix: "testnet/db"
    region: "us-east-1"

genesis:
  enabled: false  # Disable genesis download when using S3
```

## Advanced Configuration

### Custom Genesis Location

```yaml
genesis:
  enabled: true
  repository: "your-org/your-repo"
  branch: "main"
network:
  name: "custom-network"
```

### Resource Scaling

```yaml
resources:
  # Validator (high resources)
  requests:
    cpu: "12"
    memory: "24Gi"
  limits:
    cpu: "16"
    memory: "32Gi"

  # Full node (lower resources)
  requests:
    cpu: "4"
    memory: "8Gi"
  limits:
    cpu: "8"
    memory: "16Gi"
```

### Custom Seed Nodes

```yaml
fullnode:
  seeds:
    - peerId: "peer1..."
      addresses:
        - "/dns/seed1.example.com/tcp/6182/..."
    - peerId: "peer2..."
      addresses:
        - "/dns/seed2.example.com/tcp/6182/..."
```

## Upgrade Guide

### Upgrading a Running Node

```bash
# Upgrade with new values
helm upgrade validator-01 ./charts/movement-node \
  -f validator-values.yaml \
  -n movement-l1

# Check rollout status
kubectl rollout status statefulset/validator-01 -n movement-l1
```

### Migration from Old Charts

If migrating from `movement-fullnode` or `movement-validator`:

1. Note your current values
2. Uninstall old chart: `helm uninstall old-release -n movement-l1`
3. Install new unified chart with `node.type` set appropriately
4. Data persists via PVC (if using same storage class and size)

## Troubleshooting

### Validator Not Producing Blocks

```bash
kubectl logs -n movement-l1 validator-01-0 | grep -i "error\|consensus"
kubectl exec -n movement-l1 validator-01-0 -- curl -s localhost:9102/metrics | grep consensus
```

### VFN Not Syncing from Validator

```bash
# Check VFN logs for connection status
kubectl logs -n movement-l1 vfn-01-0 | grep -i "validator\|connect"

# Verify validator service is accessible
kubectl exec -n movement-l1 vfn-01-0 -- nc -zv validator-01.movement-l1.svc.cluster.local 6181
```

### Full Node Not Syncing

```bash
# Check seed connections
kubectl logs -n movement-l1 fullnode-01-0 | grep -i "seed\|sync"

# Check network connectivity
kubectl exec -n movement-l1 fullnode-01-0 -- curl -s localhost:9102/metrics | grep network_peers
```

## Parameters Reference

| Parameter | Description | Default |
|-----------|-------------|---------|
| `node.type` | Node type: validator, vfn, or fullnode | `fullnode` |
| `node.name` | Node name | `node-01` |
| `image.repository` | Container image repository | `ghcr.io/movementlabsxyz/aptos-node` |
| `image.tag` | Container image tag | `latest` |
| `network.name` | Network name (testnet, mainnet, etc.) | `testnet` |
| `storage.size` | Persistent volume size | `500Gi` |
| `resources.requests.cpu` | CPU request | `8` |
| `resources.requests.memory` | Memory request | `16Gi` |

See `values.yaml` for complete parameter documentation.

## License

Apache 2.0

## Support

- Documentation: https://docs.movementlabs.xyz
- Issues: https://github.com/movementlabsxyz/movement/issues