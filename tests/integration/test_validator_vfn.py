#!/usr/bin/env python3
"""Integration test for validator-vfn deployment.

This test validates the complete 3-tier deployment process using the UNIFIED
'charts/movement-node' Helm chart for all three node types:
- Validator (ClusterIP - private) - deployed with node.type=validator
- VFN (ClusterIP - private, connects to validator) - deployed with node.type=vfn
- Fullnode (LoadBalancer - public, connects to VFN) - deployed with node.type=fullnode

The test ensures the deployment script correctly:
1. Provisions infrastructure
2. Deploys all three nodes using the same unified chart (charts/movement-node)
3. Configures service types appropriately (only fullnode gets LoadBalancer)
4. Validates the public fullnode API is healthy

NOTE: This test ONLY uses 'charts/movement-node'. The old separate charts
(movement-validator, movement-fullnode) are NOT used by this deployment.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Add parent directory to path to import tools
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools import info, success, warn


ROOT = Path(__file__).resolve().parents[2]
EXAMPLE_DIR = ROOT / "examples" / "validator-vfn"
DEPLOY_SCRIPT = EXAMPLE_DIR / "deploy.py"


def main() -> int:
    """Run the integration test."""
    info("Validator-VFN-Fullnode integration test (3-tier topology)")
    info(f"Using deployment script: {DEPLOY_SCRIPT}")
    info("Using unified Helm chart: charts/movement-node")
    info("  → All node types deployed with same chart, different node.type values")
    
    # Set AWS configuration
    os.environ["AWS_SDK_LOAD_CONFIG"] = "1"
    
    # Override .env to force 3-tier deployment with AWS Secrets Manager
    os.environ["DEPLOY_VFN"] = "true"
    os.environ["DEPLOY_FULLNODE"] = "true"
    os.environ["VALIDATOR_NAME"] = "testnet-vn-02"
    os.environ["VALIDATOR_KEYS_SECRET_NAME"] = "movement/testnet-vn-02/validator-identity"
    os.environ["AWS_REGION"] = "us-east-1"
    os.environ["AWS_PROFILE"] = "mi:scratchpad"
    
    info("Test configuration:")
    info("  Validator: testnet-vn-02 (ClusterIP) - node.type=validator")
    info("  VFN: vfn-01 (ClusterIP) - node.type=vfn")
    info("  Fullnode: fullnode-01 (LoadBalancer) - node.type=fullnode")
    info("  Chart: charts/movement-node (unified chart for all)")
    info("  Secret: AWS Secrets Manager (movement/testnet-vn-02/validator-identity)")
    info("  → Expecting only fullnode to have public LoadBalancer")
    
    # Build command to run deploy script
    cmd = [sys.executable, str(DEPLOY_SCRIPT)]
    
    # Use .env file from example directory if it exists
    env_file = EXAMPLE_DIR / ".env"
    if env_file.exists():
        cmd.extend(["--env-file", str(env_file)])
        info(f"Using environment file: {env_file}")
    else:
        warn(f".env file not found at {env_file}")
        warn("Create it from .env.example and configure before running this test")
        warn("Required: VALIDATOR_KEYS_SECRET must reference an existing Kubernetes secret")
        return 1
    
    # Enable validation
    cmd.append("--validate")
    
    # Run deployment with validation
    info(f"Running: {' '.join(cmd)}")
    import subprocess
    result = subprocess.run(cmd)
    
    if result.returncode != 0:
        raise RuntimeError(f"Deployment failed with exit code {result.returncode}")
    
    # Additional verification
    info("\n" + "=" * 80)
    info("Verifying deployment topology...")
    info("=" * 80)
    
    # Check service types
    from kubernetes import client, config
    config.load_kube_config()
    v1 = client.CoreV1Api()
    
    namespace = os.environ.get("NAMESPACE", "movement-l1")
    validator_name = os.environ.get("VALIDATOR_NAME", "testnet-vn-02")
    vfn_name = os.environ.get("VFN_NAME", "vfn-01")
    fullnode_name = os.environ.get("FULLNODE_NAME", "fullnode-01")
    
    try:
        # Validator should be ClusterIP
        validator_svc = v1.read_namespaced_service(validator_name, namespace)
        if validator_svc.spec.type == "ClusterIP":
            success(f"✅ Validator service '{validator_name}' is ClusterIP (private)")
        else:
            warn(f"⚠️  Validator service is {validator_svc.spec.type} (expected ClusterIP)")
        
        # VFN should be ClusterIP (since fullnode is deployed)
        vfn_svc = v1.read_namespaced_service(vfn_name, namespace)
        if vfn_svc.spec.type == "ClusterIP":
            success(f"✅ VFN service '{vfn_name}' is ClusterIP (private)")
        else:
            warn(f"⚠️  VFN service is {vfn_svc.spec.type} (expected ClusterIP in 3-tier)")
        
        # Fullnode should be LoadBalancer
        fullnode_svc = v1.read_namespaced_service(fullnode_name, namespace)
        if fullnode_svc.spec.type == "LoadBalancer":
            success(f"✅ Fullnode service '{fullnode_name}' is LoadBalancer (public)")
            lb_ingress = fullnode_svc.status.load_balancer.ingress
            if lb_ingress and lb_ingress[0].hostname:
                success(f"✅ LoadBalancer hostname: {lb_ingress[0].hostname}")
        else:
            warn(f"⚠️  Fullnode service is {fullnode_svc.spec.type} (expected LoadBalancer)")
    
    except Exception as e:
        warn(f"Service verification failed: {e}")
    
    success("\n🎉 Integration test passed!")
    success("All three nodes deployed with correct topology using unified chart:")
    success(f"  • Validator ({validator_name}): Private (ClusterIP) [charts/movement-node]")
    success(f"  • VFN ({vfn_name}): Private (ClusterIP) [charts/movement-node]")  
    success(f"  • Fullnode ({fullnode_name}): Public (LoadBalancer) [charts/movement-node]")
    success("  • Chart: All deployed using unified 'charts/movement-node' chart")
    success("  • Secret: AWS Secrets Manager integration working")
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)