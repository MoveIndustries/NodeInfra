# Public Fullnode Example (Two-Stage Deployment)

This example follows a strict two-stage model:

1. Terraform provisions infrastructure.
2. Helm deploys the public fullnode workload.

## Quick Start (Automated Deployment)

The easiest way to deploy is using the automated deployment script:

```bash
cd examples/public-fullnode

# 1. Copy and configure environment file
cp .env.example .env
# Edit .env with your AWS credentials and configuration

# 2. Deploy infrastructure and workload
python3 deploy.py

# 3. Monitor deployment
kubectl get pods -n movement-l1
kubectl logs -n movement-l1 public-fullnode-0 -c s3-bootstrap -f

# 4. Clean up when done
python3 deploy.py --destroy
```

### Deployment Script Features

- ✅ Automatically provisions infrastructure if it doesn't exist
- ✅ Skips infrastructure creation if cluster already exists
- ✅ Deploys Helm chart with proper bootstrap configuration
- ✅ Waits for EKS cluster to become active
- ✅ Supports custom environment files
- ✅ Clean destroy with Helm cleanup

### Script Options

```bash
# Use custom environment file
python3 deploy.py --env-file production.env

# Force infrastructure creation even if cluster exists
python3 deploy.py --force-create

# Destroy deployment
python3 deploy.py --destroy
```

## Manual Deployment (Advanced)

If you prefer manual control over each stage:

### Stage 1: Provision Infrastructure

```bash
cd examples/public-fullnode
terraform init
terraform plan
terraform apply
```

Useful outputs:

```bash
terraform output -raw cluster_name
terraform output -raw region
terraform output -raw public_fullnode_namespace
terraform output -raw public_fullnode_release_name
terraform output -raw fullnode_bootstrap_enabled
terraform output -raw fullnode_service_account_name
terraform output -raw fullnode_s3_role_arn
```

## Stage 2: Deploy Workload with Helm

From repo root:

```bash
CLUSTER_NAME=$(terraform -chdir=examples/public-fullnode output -raw cluster_name)
REGION=$(terraform -chdir=examples/public-fullnode output -raw region)
NAMESPACE=$(terraform -chdir=examples/public-fullnode output -raw public_fullnode_namespace)
RELEASE_NAME=$(terraform -chdir=examples/public-fullnode output -raw public_fullnode_release_name)
SERVICE_NAME=$(terraform -chdir=examples/public-fullnode output -raw public_fullnode_service_name)

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

helm upgrade --install "$RELEASE_NAME" ./charts/movement-node \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set node.type=fullnode \
  --set node.name="$SERVICE_NAME" \
  --set network.name=testnet \
  --set network.chainId=250 \
  --set-file config.inline=./configs/testnet.pfn-restore.yaml
```

If bootstrap is enabled in Terraform, add these Helm overrides:

```bash
SERVICE_ACCOUNT_NAME=$(terraform -chdir=examples/public-fullnode output -raw fullnode_service_account_name)
S3_ROLE_ARN=$(terraform -chdir=examples/public-fullnode output -raw fullnode_s3_role_arn)
S3_URI=$(terraform -chdir=examples/public-fullnode output -raw fullnode_bootstrap_s3_uri)
S3_REGION=$(terraform -chdir=examples/public-fullnode output -raw fullnode_bootstrap_region)

# Parse S3 URI
S3_BUCKET=$(echo "$S3_URI" | sed 's|s3://||' | cut -d'/' -f1)
S3_PREFIX=$(echo "$S3_URI" | sed 's|s3://||' | cut -d'/' -f2-)

helm upgrade --install "$RELEASE_NAME" ./charts/movement-node \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set node.type=fullnode \
  --set node.name="$SERVICE_NAME" \
  --set network.name=testnet \
  --set network.chainId=250 \
  --set-file config.inline=./configs/testnet.pfn-restore.yaml \
  --set serviceAccount.create=true \
  --set serviceAccount.name="$SERVICE_ACCOUNT_NAME" \
  --set serviceAccount.annotations.eks\.amazonaws\.com/role-arn="$S3_ROLE_ARN" \
  --set bootstrap.enabled=true \
  --set bootstrap.s3.bucket="$S3_BUCKET" \
  --set bootstrap.s3.prefix="$S3_PREFIX" \
  --set bootstrap.s3.region="$S3_REGION"
```

## Cleanup

```bash
helm uninstall "$(terraform -chdir=examples/public-fullnode output -raw public_fullnode_release_name)" \
  -n "$(terraform -chdir=examples/public-fullnode output -raw public_fullnode_namespace)" || true

terraform -chdir=examples/public-fullnode destroy
```
