#!/usr/bin/env python3
"""
Deployment configuration for Movement validator cluster.

This script intelligently deploys validator, VFN, and optionally fullnode
with correct service type configuration based on the topology.

Supported topologies:
- Validator only: Validator (ClusterIP)
- Validator + VFN: Validator (ClusterIP), VFN (LoadBalancer)
- Validator + VFN + Fullnode: Validator (ClusterIP), VFN (ClusterIP), Fullnode (LoadBalancer)
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional

# Add parent directory to path to import tools
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools import ClusterManager, run_deployment_cli, info, success


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parents[1]
CHART_DIR = ROOT_DIR / "charts" / "movement-node"


def build_terraform_vars(env_vars: dict) -> dict:
    """Map environment variables to Terraform variables."""
    variables = {}
    
    if "VALIDATOR_NAME" in env_vars:
        variables["validator_name"] = env_vars["VALIDATOR_NAME"]
    if "AWS_REGION" in env_vars:
        variables["region"] = env_vars["AWS_REGION"]
    if "VPC_CIDR" in env_vars:
        variables["vpc_cidr"] = env_vars["VPC_CIDR"]
    
    # DNS configuration
    enable_dns = env_vars.get("ENABLE_DNS", "false").lower() in ("true", "1", "yes")
    variables["enable_dns"] = enable_dns
    if enable_dns and "DNS_ZONE_NAME" in env_vars:
        variables["dns_zone_name"] = env_vars["DNS_ZONE_NAME"]
    else:
        variables["dns_zone_name"] = ""
    
    # Node configuration
    if "NODE_INSTANCE_TYPES" in env_vars:
        variables["node_instance_types"] = [t.strip() for t in env_vars["NODE_INSTANCE_TYPES"].split(",")]
    
    # Node sizing based on topology
    deploy_vfn = env_vars.get("DEPLOY_VFN", "true").lower() in ("true", "1", "yes")
    deploy_fullnode = env_vars.get("DEPLOY_FULLNODE", "false").lower() in ("true", "1", "yes")
    
    # Calculate required nodes
    node_count = 1  # Validator
    if deploy_vfn:
        node_count += 1
    if deploy_fullnode:
        node_count += 1
    
    variables["node_desired_size"] = node_count
    variables["node_min_size"] = node_count
    variables["node_max_size"] = node_count + 2
    
    return variables


def deploy_node(
    cluster: ClusterManager,
    node_type: str,
    node_name: str,
    namespace: str,
    service_type: Optional[str] = None,
    validator_service: Optional[str] = None,
    vfn_service: Optional[str] = None,
    validator_keys_secret: Optional[str] = None,
) -> None:
    """Deploy a single node with appropriate configuration."""
    info(f"Deploying {node_type}: {node_name}")
    
    # Base configuration
    set_values = {
        "node.type": node_type,
        "node.name": node_name,
        "network.name": "testnet",
        "network.chainId": "126",
        "storage.create": "true" if node_type == "validator" else "false",
        "storage.storageClassName": "gp3",
        "storage.parameters.type": "gp3",
        "storage.parameters.iops": "6000",
        "storage.parameters.throughput": "500",
    }
    
    # Override service type if specified
    if service_type:
        set_values["service.type"] = service_type
        info(f"  Service type: {service_type}")
    
    # Node-specific configuration
    if node_type == "validator":
        if not validator_keys_secret:
            raise ValueError("validator_keys_secret required for validator deployment")
        set_values["validator.identity.existingSecret"] = validator_keys_secret
        set_values["genesis.enabled"] = "true"
        
    elif node_type == "vfn":
        if not validator_service:
            raise ValueError("validator_service required for VFN deployment")
        set_values["vfn.validator.serviceName"] = validator_service
        set_values["vfn.validator.namespace"] = namespace
        set_values["genesis.enabled"] = "true"
        
    elif node_type == "fullnode":
        if vfn_service:
            # Configure to sync from VFN in same cluster
            info(f"  Upstream: {vfn_service}")
        set_values["genesis.enabled"] = "true"
    
    # Deploy with Helm
    config_file = ROOT_DIR / "charts" / "movement-node" / "files" / f"{node_type}.yaml"
    
    cluster.helm.upgrade_install(
        release_name=node_name,
        namespace=namespace,
        create_namespace=True,
        set_values=set_values,
        set_files={"config.inline": config_file} if config_file.exists() else None,
    )
    
    success(f"{node_type.upper()} '{node_name}' deployed successfully")


def deploy(env_vars: dict, force_create: bool, validate: bool) -> None:
    """Deploy validator cluster with intelligent topology handling."""
    cluster = ClusterManager(SCRIPT_DIR, CHART_DIR, ROOT_DIR)
    
    # Get topology configuration
    deploy_vfn = env_vars.get("DEPLOY_VFN", "true").lower() in ("true", "1", "yes")
    deploy_fullnode = env_vars.get("DEPLOY_FULLNODE", "false").lower() in ("true", "1", "yes")
    
    # Deployment names
    validator_name = env_vars.get("VALIDATOR_NAME", "validator-01")
    vfn_name = env_vars.get("VFN_NAME", "vfn-01")
    fullnode_name = env_vars.get("FULLNODE_NAME", "fullnode-01")
    namespace = env_vars.get("NAMESPACE", "movement-l1")
    validator_keys_secret = env_vars.get("VALIDATOR_KEYS_SECRET", "validator-identity")
    
    # Display deployment plan
    info("Deployment Topology:")
    info(f"  Validator: {validator_name} (ClusterIP - private)")
    if deploy_vfn and deploy_fullnode:
        info(f"  VFN: {vfn_name} (ClusterIP - private)")
        info(f"  Fullnode: {fullnode_name} (LoadBalancer - public)")
        info("  → 3-tier setup: External clients access fullnode")
    elif deploy_vfn:
        info(f"  VFN: {vfn_name} (LoadBalancer - public)")
        info("  → 2-tier setup: External clients access VFN")
    else:
        info("  → Validator-only setup: No public access")
    
    # Step 1: Provision infrastructure
    terraform_vars = build_terraform_vars(env_vars)
    outputs = cluster.terraform.get_outputs() or {}
    
    if not force_create and outputs:
        info("Infrastructure already exists, skipping Terraform")
    else:
        cluster.terraform.init(upgrade=True)
        cluster.terraform.validate()
        cluster.terraform.apply(var_args=terraform_vars, auto_approve=True)
        outputs = cluster.terraform.get_outputs()
    
    # Update kubeconfig
    cluster_name = outputs.get("cluster_name", f"{env_vars.get('VALIDATOR_NAME', 'validator')}-cluster")
    region = outputs.get("region", env_vars.get("AWS_REGION", "us-east-1"))
    
    cluster.eks.cluster_name = cluster_name
    cluster.eks.region = region
    cluster.eks.wait_until_active()
    cluster.eks.update_kubeconfig()
    
    # Step 2: Deploy nodes in order
    # Deploy validator first (always ClusterIP)
    deploy_node(
        cluster=cluster,
        node_type="validator",
        node_name=validator_name,
        namespace=namespace,
        service_type="ClusterIP",
        validator_keys_secret=validator_keys_secret,
    )
    
    # Deploy VFN if requested
    if deploy_vfn:
        # VFN service type depends on whether fullnode is deployed
        vfn_service_type = "ClusterIP" if deploy_fullnode else "LoadBalancer"
        
        deploy_node(
            cluster=cluster,
            node_type="vfn",
            node_name=vfn_name,
            namespace=namespace,
            service_type=vfn_service_type,
            validator_service=validator_name,
        )
    
    # Deploy fullnode if requested
    if deploy_fullnode:
        deploy_node(
            cluster=cluster,
            node_type="fullnode",
            node_name=fullnode_name,
            namespace=namespace,
            service_type="LoadBalancer",
            vfn_service=vfn_name if deploy_vfn else None,
        )
    
    # Step 3: Validation (if requested)
    if validate:
        # Determine which node to validate (the public-facing one)
        if deploy_fullnode:
            validate_service = fullnode_name
        elif deploy_vfn:
            validate_service = vfn_name
        else:
            # Validator-only, no public API to validate
            success("Deployment complete (validator-only, no public API)")
            return
        
        from tools.validation import validate_deployment
        
        validate_deployment(
            namespace=namespace,
            service_name=validate_service,
            pod_timeout=3600,
            lb_retries=60,
        )
    
    success("Deployment complete!")
    
    # Print access information
    info("\n" + "=" * 80)
    info("Access Information:")
    info("=" * 80)
    
    if deploy_fullnode:
        info(f"\n🌐 Public Access: Fullnode LoadBalancer")
        info(f"   Service: {fullnode_name}")
        info(f"   kubectl get svc {fullnode_name} -n {namespace}")
    elif deploy_vfn:
        info(f"\n🌐 Public Access: VFN LoadBalancer")
        info(f"   Service: {vfn_name}")
        info(f"   kubectl get svc {vfn_name} -n {namespace}")
    
    info(f"\n📊 Check pod status:")
    info(f"   kubectl get pods -n {namespace}")
    
    info(f"\n📝 View logs:")
    info(f"   kubectl logs {validator_name}-0 -n {namespace}")
    if deploy_vfn:
        info(f"   kubectl logs {vfn_name}-0 -n {namespace}")
    if deploy_fullnode:
        info(f"   kubectl logs {fullnode_name}-0 -n {namespace}")
    info("=" * 80 + "\n")


def destroy(env_vars: dict) -> None:
    """Destroy all deployed resources."""
    cluster = ClusterManager(SCRIPT_DIR, CHART_DIR, ROOT_DIR)
    
    namespace = env_vars.get("NAMESPACE", "movement-l1")
    validator_name = env_vars.get("VALIDATOR_NAME", "validator-01")
    vfn_name = env_vars.get("VFN_NAME", "vfn-01")
    fullnode_name = env_vars.get("FULLNODE_NAME", "fullnode-01")
    deploy_vfn = env_vars.get("DEPLOY_VFN", "true").lower() in ("true", "1", "yes")
    deploy_fullnode = env_vars.get("DEPLOY_FULLNODE", "false").lower() in ("true", "1", "yes")
    
    # Uninstall Helm releases in reverse order
    if deploy_fullnode:
        cluster.helm.uninstall(fullnode_name, namespace)
    if deploy_vfn:
        cluster.helm.uninstall(vfn_name, namespace)
    cluster.helm.uninstall(validator_name, namespace)
    
    # Destroy Terraform infrastructure
    terraform_vars = build_terraform_vars(env_vars)
    cluster.destroy(terraform_vars)


if __name__ == "__main__":
    sys.exit(run_deployment_cli(deploy, destroy, SCRIPT_DIR / ".env"))