#!/bin/bash
#
# Integration test for Milestone 2: Public Fullnode
#
# This script:
# 1. Deploys the public fullnode infrastructure
# 2. Validates the public fullnode API responds correctly
# 3. Cleans up all resources
#
# Usage: ./test-hello-world.sh [--skip-destroy]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="${SCRIPT_DIR}/../../examples/public-fullnode"
SKIP_DESTROY=false
MAX_RETRIES=60
RETRY_INTERVAL=10
ENABLE_DNS="${ENABLE_DNS:-false}"
TF_VAR_ARGS=()
if [ "$ENABLE_DNS" != "true" ]; then
  TF_VAR_ARGS+=("-var" "enable_dns=false" "-var" "dns_zone_name=" "-var" "fullnode_dns_name=")
fi
VALIDATOR_NAME="${VALIDATOR_NAME:-}"
if [ -n "$VALIDATOR_NAME" ]; then
  TF_VAR_ARGS+=("-var" "validator_name=$VALIDATOR_NAME")
fi

STATE_DIR_TEMP=""
if [ -z "${STATE_PATH:-}" ]; then
  STATE_DIR_TEMP="$(mktemp -d -t tfstate.XXXXXX)"
  STATE_PATH="${STATE_DIR_TEMP}/terraform.tfstate"
fi
STATE_ARGS=("-state=$STATE_PATH")

# Parse arguments
for arg in "$@"; do
  case $arg in
    --skip-destroy)
      SKIP_DESTROY=true
      shift
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

export TMPDIR="/tmp"
export AWS_SDK_LOAD_CONFIG=1

TF_PLUGIN_MIRROR_DIR_DEFAULT="${HOME}/.terraform.d/plugin-cache"
TF_PLUGIN_MIRROR_DIR="${TF_PLUGIN_MIRROR_DIR:-$TF_PLUGIN_MIRROR_DIR_DEFAULT}"
if [ "${TF_DISABLE_PLUGIN_MIRROR:-false}" = "true" ]; then
  TF_PLUGIN_MIRROR_DIR=""
fi
TF_CLI_CONFIG_FILE_TEMP=""
if [ -n "$TF_PLUGIN_MIRROR_DIR" ] && [ -d "$TF_PLUGIN_MIRROR_DIR" ]; then
  TF_CLI_CONFIG_FILE_TEMP="$(mktemp -t terraformrc.XXXXXX)"
  cat > "$TF_CLI_CONFIG_FILE_TEMP" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "$TF_PLUGIN_MIRROR_DIR"
    include = ["registry.terraform.io/hashicorp/*"]
  }
  direct {
    exclude = ["registry.terraform.io/hashicorp/*"]
  }
}
EOF
  export TF_CLI_CONFIG_FILE="$TF_CLI_CONFIG_FILE_TEMP"
  log_info "Using Terraform provider mirror at $TF_PLUGIN_MIRROR_DIR"
fi

AWS_SHARED_CREDENTIALS_FILE_TEMP=""
if [ -n "${AWS_PROFILE:-}" ] && [ -f "${HOME}/.aws/config" ]; then
  if awk -v prof="$AWS_PROFILE" '
    BEGIN { inprof=0; found=0 }
    $0 ~ /^\[profile / { inprof = ($0 == "[profile " prof "]"); next }
    $0 ~ /^\[/ { inprof=0 }
    inprof && $0 ~ /^sso_/ { found=1 }
    END { exit !found }
  ' "${HOME}/.aws/config"; then
    AWS_SHARED_CREDENTIALS_FILE_TEMP="$(mktemp -t awscreds.XXXXXX)"
    export AWS_SHARED_CREDENTIALS_FILE="$AWS_SHARED_CREDENTIALS_FILE_TEMP"
  fi
fi

HELM_VALUES_FILE=""

cleanup() {
  if [ "$SKIP_DESTROY" = false ]; then
    log_info "Cleaning up resources..."
    cd "$EXAMPLE_DIR"
    terraform destroy -auto-approve "${TF_VAR_ARGS[@]}" "${STATE_ARGS[@]}" || log_warn "Cleanup failed, manual cleanup may be required"
  else
    log_warn "Skipping cleanup (--skip-destroy flag set)"
  fi

  if [ -n "$TF_CLI_CONFIG_FILE_TEMP" ] && [ -f "$TF_CLI_CONFIG_FILE_TEMP" ]; then
    rm -f "$TF_CLI_CONFIG_FILE_TEMP"
  fi
  if [ -n "$AWS_SHARED_CREDENTIALS_FILE_TEMP" ] && [ -f "$AWS_SHARED_CREDENTIALS_FILE_TEMP" ]; then
    rm -f "$AWS_SHARED_CREDENTIALS_FILE_TEMP"
  fi
  if [ -n "$HELM_VALUES_FILE" ] && [ -f "$HELM_VALUES_FILE" ]; then
    rm -f "$HELM_VALUES_FILE"
  fi

  if [ -n "$STATE_DIR_TEMP" ] && [ -d "$STATE_DIR_TEMP" ]; then
    rm -rf "$STATE_DIR_TEMP"
  fi
}

# Trap errors and cleanup
trap 'log_error "Test failed!"; cleanup; exit 1' ERR
trap 'log_warn "Test interrupted, cleaning up..."; cleanup; exit 1' INT TERM

log_info "================================"
log_info "M2 Integration Test: Public Fullnode"
log_info "================================"
echo ""

# Step 1: Navigate to example directory
log_info "Step 1: Navigating to public-fullnode example..."
cd "$EXAMPLE_DIR"
pwd

# Step 2: Initialize Terraform
log_info "Step 2: Initializing Terraform..."
terraform init -upgrade

# Step 3: Validate configuration
log_info "Step 3: Validating Terraform configuration..."
terraform validate

# Step 4: Plan infrastructure
log_info "Step 4: Planning infrastructure..."
terraform plan "${TF_VAR_ARGS[@]}" "${STATE_ARGS[@]}" -out=tfplan

# Step 5: Apply infrastructure
log_info "Step 5: Deploying infrastructure (this takes ~10-20 minutes)..."
terraform apply -auto-approve "${STATE_ARGS[@]}" tfplan

# Step 6: Get outputs
log_info "Step 6: Retrieving outputs..."
API_PORT=$(terraform output "${STATE_ARGS[@]}" -raw public_fullnode_api_port)
NAMESPACE=$(terraform output "${STATE_ARGS[@]}" -raw public_fullnode_namespace)
SERVICE_NAME=$(terraform output "${STATE_ARGS[@]}" -raw public_fullnode_service_name)
RELEASE_NAME=$(terraform output "${STATE_ARGS[@]}" -raw public_fullnode_release_name)
CLUSTER_NAME=$(terraform output "${STATE_ARGS[@]}" -raw cluster_name)
REGION=$(terraform output "${STATE_ARGS[@]}" -json | jq -r '.configure_kubectl.value' | awk '{for(i=1;i<=NF;i++) if($i=="--region"){print $(i+1); exit}}')

HELM_VALUES_FILE="$(mktemp -t fullnode-values.XXXXXX)"
terraform output "${STATE_ARGS[@]}" -raw public_fullnode_helm_values > "$HELM_VALUES_FILE"

log_info "API Port: $API_PORT"
log_info "Cluster Name: $CLUSTER_NAME"
log_info "Namespace: $NAMESPACE"
log_info "Service: $SERVICE_NAME"
log_info "Helm Release: $RELEASE_NAME"
LB_HOSTNAME=""

# Step 7: Deploy Helm chart
log_info "Step 7: Deploying Helm release..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" > /dev/null 2>&1
CHART_DIR="${EXAMPLE_DIR}/../../charts/movement-fullnode"
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" --namespace "$NAMESPACE" --create-namespace -f "$HELM_VALUES_FILE"

# Step 8: Validate Kubernetes resources
log_info "Step 8: Validating Kubernetes resources..."

# Check nodes
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -ge 1 ]; then
  log_info "✓ Found $NODE_COUNT node(s)"
else
  log_error "✗ No nodes found in cluster"
  cleanup
  exit 1
fi

# Check namespace
if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  log_info "✓ Namespace found ($NAMESPACE)"
else
  log_error "✗ Namespace not found: $NAMESPACE"
  cleanup
  exit 1
fi

# Wait for pod readiness
log_info "Waiting for public fullnode pod to become Ready..."
if kubectl wait --for=condition=Ready pod -n "$NAMESPACE" -l app="$SERVICE_NAME" --timeout=600s > /dev/null 2>&1; then
  log_info "✓ Public fullnode pod is Ready"
else
  log_error "✗ Public fullnode pod did not become Ready"
  kubectl get pods -n "$NAMESPACE" -o wide || true
  kubectl describe pod -n "$NAMESPACE" -l app="$SERVICE_NAME" || true
  kubectl logs -n "$NAMESPACE" -l app="$SERVICE_NAME" -c s3-bootstrap --previous --tail=200 || true
  kubectl logs -n "$NAMESPACE" -l app="$SERVICE_NAME" -c s3-bootstrap --tail=200 || true
  kubectl logs -n "$NAMESPACE" -l app="$SERVICE_NAME" -c genesis-setup --tail=200 || true
  cleanup
  exit 1
fi

# Check service
SVC_COUNT=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" --no-headers 2>/dev/null | wc -l)
if [ "$SVC_COUNT" -eq 1 ]; then
  log_info "✓ Service found ($SERVICE_NAME)"
else
  log_error "✗ Service not found"
  cleanup
  exit 1
fi

# Step 9: Wait for load balancer to be ready
log_info "Step 9: Waiting for load balancer to become healthy..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if [ -n "$NAMESPACE" ] && [ -n "$SERVICE_NAME" ]; then
    LB_HOSTNAME=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [ -z "$LB_HOSTNAME" ]; then
      LB_HOSTNAME=$(kubectl get svc -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    fi
  fi

  if [ "$LB_HOSTNAME" != "pending" ] && [ -n "$LB_HOSTNAME" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_HOSTNAME:$API_PORT/v1" || true)
    if [ -z "$HTTP_STATUS" ]; then
      HTTP_STATUS="000"
    fi

    if [ "$HTTP_STATUS" == "200" ]; then
      log_info "Load balancer is healthy (HTTP $HTTP_STATUS)"
      break
    else
      log_warn "Load balancer not ready yet (HTTP $HTTP_STATUS), retrying in ${RETRY_INTERVAL}s... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    fi
  else
    log_warn "Load balancer hostname is pending, retrying in ${RETRY_INTERVAL}s... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  fi

  sleep $RETRY_INTERVAL
  RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  log_error "Load balancer did not become healthy within expected time"
  cleanup
  exit 1
fi

# Step 10: Test HTTP endpoint
log_info "Step 10: Testing public fullnode API endpoint..."
RESPONSE=$(curl -s "http://$LB_HOSTNAME:$API_PORT/v1")
LEDGER_VERSION=$(echo "$RESPONSE" | jq -r '.ledger_version // empty' || true)
CHAIN_ID=$(echo "$RESPONSE" | jq -r '.chain_id // empty' || true)

if [[ "$LEDGER_VERSION" =~ ^[0-9]+$ ]]; then
  log_info "✓ Public fullnode API test PASSED (ledger_version=$LEDGER_VERSION, chain_id=$CHAIN_ID)"
else
  log_error "✗ Public fullnode API test FAILED - unexpected response"
  log_error "Expected: JSON with ledger_version"
  log_error "Got: $RESPONSE"
  cleanup
  exit 1
fi

# Step 11: Cleanup
if [ "$SKIP_DESTROY" = false ]; then
  log_info "Step 11: Destroying infrastructure..."
  terraform destroy -auto-approve "${TF_VAR_ARGS[@]}" "${STATE_ARGS[@]}"
  log_info "✓ Cleanup completed"
else
  log_warn "Step 11: Skipping cleanup (--skip-destroy flag set)"
  log_warn "Remember to run 'terraform destroy' manually to avoid charges"
fi

# Success!
echo ""
log_info "================================"
log_info "✓ All M2 tests PASSED"
log_info "================================"
echo ""
log_info "Summary:"
log_info "  - VPC created successfully"
log_info "  - EKS cluster deployed"
log_info "  - Public fullnode API responding"
log_info "  - Load balancer healthy"
log_info "  - Kubernetes resources validated"
log_info "  - Infrastructure cleaned up"
echo ""
