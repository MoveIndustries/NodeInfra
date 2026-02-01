#!/bin/bash
#
# Integration test for Milestone 1: Hello World Example
#
# This script:
# 1. Deploys the hello-world infrastructure
# 2. Validates the HTTP endpoint responds correctly
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
EXAMPLE_DIR="${SCRIPT_DIR}/../../examples/hello-world"
SKIP_DESTROY=false
MAX_RETRIES=60
RETRY_INTERVAL=10

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

cleanup() {
  if [ "$SKIP_DESTROY" = false ]; then
    log_info "Cleaning up resources..."
    cd "$EXAMPLE_DIR"
    terraform destroy -auto-approve || log_warn "Cleanup failed, manual cleanup may be required"
  else
    log_warn "Skipping cleanup (--skip-destroy flag set)"
  fi
}

# Trap errors and cleanup
trap 'log_error "Test failed!"; cleanup; exit 1' ERR
trap 'log_warn "Test interrupted, cleaning up..."; cleanup; exit 1' INT TERM

log_info "================================"
log_info "M1 Integration Test: Hello World"
log_info "================================"
echo ""

# Step 1: Navigate to example directory
log_info "Step 1: Navigating to hello-world example..."
cd "$EXAMPLE_DIR"
pwd

# Step 2: Initialize Terraform
log_info "Step 2: Initializing Terraform..."
terraform init

# Step 3: Validate configuration
log_info "Step 3: Validating Terraform configuration..."
terraform validate

# Step 4: Plan infrastructure
log_info "Step 4: Planning infrastructure..."
terraform plan -out=tfplan

# Step 5: Apply infrastructure
log_info "Step 5: Deploying infrastructure (this takes ~10-15 minutes)..."
terraform apply -auto-approve tfplan

# Step 6: Get outputs
log_info "Step 6: Retrieving outputs..."
LB_HOSTNAME=$(terraform output -raw load_balancer_hostname)
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -json | jq -r '.configure_kubectl.value' | awk '{for(i=1;i<=NF;i++) if($i=="--region"){print $(i+1); exit}}')

log_info "Load Balancer Hostname: $LB_HOSTNAME"
log_info "Cluster Name: $CLUSTER_NAME"

# Step 7: Wait for load balancer to be ready
log_info "Step 7: Waiting for load balancer to become healthy..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if [ "$LB_HOSTNAME" != "pending" ] && [ -n "$LB_HOSTNAME" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$LB_HOSTNAME" || true)
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
    LB_HOSTNAME=$(terraform output -raw load_balancer_hostname)
  fi

  sleep $RETRY_INTERVAL
  RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  log_error "Load balancer did not become healthy within expected time"
  cleanup
  exit 1
fi

# Step 8: Test HTTP endpoint
log_info "Step 8: Testing HTTP endpoint..."
RESPONSE=$(curl -s "http://$LB_HOSTNAME")
log_info "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q "Hello World"; then
  log_info "✓ HTTP endpoint test PASSED"
else
  log_error "✗ HTTP endpoint test FAILED - unexpected response"
  log_error "Expected: 'Hello World' in response"
  log_error "Got: $RESPONSE"
  cleanup
  exit 1
fi

# Step 9: Validate Kubernetes resources
log_info "Step 9: Validating Kubernetes resources..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" > /dev/null 2>&1

# Check nodes
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -ge 1 ]; then
  log_info "✓ Found $NODE_COUNT node(s)"
else
  log_error "✗ No nodes found in cluster"
  cleanup
  exit 1
fi

# Check pods
POD_COUNT=$(kubectl get pods -n demo --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$POD_COUNT" -ge 2 ]; then
  log_info "✓ Found $POD_COUNT running pod(s)"
else
  log_error "✗ Expected 2 running pods, found $POD_COUNT"
  cleanup
  exit 1
fi

# Check service
SVC_COUNT=$(kubectl get svc -n demo hello-world --no-headers 2>/dev/null | wc -l)
if [ "$SVC_COUNT" -eq 1 ]; then
  log_info "✓ Service found"
else
  log_error "✗ Service not found"
  cleanup
  exit 1
fi

# Step 10: Cleanup
if [ "$SKIP_DESTROY" = false ]; then
  log_info "Step 10: Destroying infrastructure..."
  terraform destroy -auto-approve
  log_info "✓ Cleanup completed"
else
  log_warn "Step 10: Skipping cleanup (--skip-destroy flag set)"
  log_warn "Remember to run 'terraform destroy' manually to avoid charges"
fi

# Success!
echo ""
log_info "================================"
log_info "✓ All M1 tests PASSED"
log_info "================================"
echo ""
log_info "Summary:"
log_info "  - VPC created successfully"
log_info "  - EKS cluster deployed"
log_info "  - Hello World service responding"
log_info "  - Load balancer healthy"
log_info "  - Kubernetes resources validated"
log_info "  - Infrastructure cleaned up"
echo ""
