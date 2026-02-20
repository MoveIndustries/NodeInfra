# Movement Infrastructure Tools

Common utilities for deploying and managing Movement infrastructure.

## Overview

This package provides reusable Python tools for:
- **Terraform operations**: Initialize, plan, apply, destroy infrastructure
- **AWS EKS management**: Check cluster status, wait for readiness, update kubeconfig
- **Helm deployments**: Install/upgrade/uninstall Helm releases
- **Common utilities**: Logging, command execution, environment variable handling

## Usage

### Basic Example

```python
from pathlib import Path
from tools import TerraformManager, EKSManager, HelmManager

# Provision infrastructure with Terraform
tf = TerraformManager(Path("examples/public-fullnode"))
tf.init()
tf.validate()
tf.apply()

# Get outputs
outputs = tf.get_outputs()
cluster_name = outputs["cluster_name"]
region = outputs["region"]

# Manage EKS cluster
eks = EKSManager(cluster_name, region)
eks.wait_until_active()
eks.update_kubeconfig()

# Deploy with Helm
helm = HelmManager(Path("charts/movement-fullnode"))
helm.upgrade_install(
    release_name="public-fullnode",
    namespace="movement-l1",
    set_values={
        "fullnameOverride": "public-fullnode",
        "node.id": "public-fullnode",
    },
    set_files={
        "config.inline": Path("configs/testnet.pfn-restore.yaml")
    }
)
```

### TerraformManager

```python
from tools import TerraformManager

tf = TerraformManager(working_dir=Path("terraform/"))

# Initialize
tf.init(upgrade=True)

# Validate
tf.validate()

# Plan
var_args = tf.build_var_args({
    "validator_name": "demo",
    "region": "us-east-1",
    "enable_dns": False
})
tf.plan(var_args=var_args)

# Apply
tf.apply(var_args=var_args, auto_approve=True)

# Get outputs
outputs = tf.get_outputs()
cluster_name = outputs.get("cluster_name")

# Destroy
tf.destroy(var_args=var_args, auto_approve=True)
```

### EKSManager

```python
from tools import EKSManager

eks = EKSManager(cluster_name="my-cluster", region="us-east-1")

# Check if cluster exists
if eks.cluster_exists():
    print("Cluster exists!")

# Get cluster status
status = eks.get_cluster_status()
print(f"Cluster status: {status}")

# Wait for cluster to become active
eks.wait_until_active(timeout=1800)

# Update kubeconfig
eks.update_kubeconfig()
```

### HelmManager

```python
from tools import HelmManager
from pathlib import Path

helm = HelmManager(chart_dir=Path("charts/my-chart"))

# Install or upgrade release
helm.upgrade_install(
    release_name="my-release",
    namespace="my-namespace",
    set_values={
        "image.tag": "v1.0.0",
        "replicas": "3",
    },
    set_files={
        "config.yaml": Path("configs/production.yaml")
    },
    create_namespace=True,
    wait=True,
    timeout="10m"
)

# Uninstall release
helm.uninstall(
    release_name="my-release",
    namespace="my-namespace"
)

# List releases
helm.list_releases(namespace="my-namespace")
```

### Utilities

```python
from tools import info, success, error, warn, run_command, load_env_file

# Logging
info("Starting deployment")
success("Deployment completed")
warn("Resource limit reached")
error("Failed to connect")

# Run commands
result = run_command(
    ["kubectl", "get", "pods"],
    cwd=Path("/path/to/dir"),
    capture=True,
    check=True
)

# Load environment variables
env_vars = load_env_file(Path(".env"))
aws_profile = env_vars.get("AWS_PROFILE")
```

## Integration Test Example

See `tests/integration/test_public_fullnode.py` for a complete example of using these tools in an integration test.

## Deployment Script Example

```python
#!/usr/bin/env python3
from pathlib import Path
from tools import TerraformManager, EKSManager, HelmManager, info, success

# Provision infrastructure
tf = TerraformManager(Path("examples/public-fullnode"))
tf.init()
tf.apply()
outputs = tf.get_outputs()

# Wait for EKS cluster
eks = EKSManager(outputs["cluster_name"], outputs["region"])
eks.wait_until_active()
eks.update_kubeconfig()

# Deploy workload
helm = HelmManager(Path("charts/movement-fullnode"))
helm.upgrade_install(
    release_name=outputs["public_fullnode_release_name"],
    namespace=outputs["public_fullnode_namespace"],
    set_values={
        "fullnameOverride": outputs["public_fullnode_service_name"],
    }
)

success("Deployment completed!")
```

## Requirements

- Python 3.8+
- terraform
- aws CLI
- kubectl
- helm

## Error Handling

All tools use the common `fail()` function which prints an error message and exits with code 1. This ensures consistent error handling across all tools.

```python
from tools import fail

if not cluster_exists:
    fail("Cluster not found")
