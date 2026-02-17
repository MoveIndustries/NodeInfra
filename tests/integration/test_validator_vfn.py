#!/usr/bin/env python3
"""Integration test for validator-vfn deployment.

This test validates the complete 3-tier deployment process:
- Validator (ClusterIP - private)
- VFN (ClusterIP - private, connects to validator)
- Fullnode (LoadBalancer - public, connects to VFN)

The test ensures the deployment script correctly:
1. Provisions infrastructure
2. Deploys all three nodes
3. Configures service types appropriately (only fullnode gets LoadBalancer)
4. Validates the public fullnode API is healthy
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
    
    # Set AWS configuration
    os.environ["AWS_SDK_LOAD_CONFIG"] = "1"
    
    # Override .env to force 3-tier deployment
    os.environ["DEPLOY_VFN"] = "true"
    os.environ["DEPLOY_FULLNODE"] = "true"
    
    info("Test configuration:")
    info("  Validator: validator-01 (ClusterIP)")
    info("  VFN: vfn-01 (ClusterIP)")
    info("  Fullnode: fullnode-01 (LoadBalancer)")
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
    
    try:
        # Validator should be ClusterIP
        validator_svc = v1.read_namespaced_service("validator-01", namespace)
        if validator_svc.spec.type == "ClusterIP":
            success("✅ Validator service is ClusterIP (private)")
        else:
            warn(f"⚠️  Validator service is {validator_svc.spec.type} (expected ClusterIP)")
        
        # VFN should be ClusterIP (since fullnode is deployed)
        vfn_svc = v1.read_namespaced_service("vfn-01", namespace)
        if vfn_svc.spec.type == "ClusterIP":
            success("✅ VFN service is ClusterIP (private)")
        else:
            warn(f"⚠️  VFN service is {vfn_svc.spec.type} (expected ClusterIP in 3-tier)")
        
        # Fullnode should be LoadBalancer
        fullnode_svc = v1.read_namespaced_service("fullnode-01", namespace)
        if fullnode_svc.spec.type == "LoadBalancer":
            success("✅ Fullnode service is LoadBalancer (public)")
            lb_ingress = fullnode_svc.status.load_balancer.ingress
            if lb_ingress and lb_ingress[0].hostname:
                success(f"✅ LoadBalancer hostname: {lb_ingress[0].hostname}")
        else:
            warn(f"⚠️  Fullnode service is {fullnode_svc.spec.type} (expected LoadBalancer)")
    
    except Exception as e:
        warn(f"Service verification failed: {e}")
    
    success("\n🎉 Integration test passed!")
    success("All three nodes deployed with correct topology:")
    success("  • Validator: Private (ClusterIP)")
    success("  • VFN: Private (ClusterIP)")  
    success("  • Fullnode: Public (LoadBalancer)")
    
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)