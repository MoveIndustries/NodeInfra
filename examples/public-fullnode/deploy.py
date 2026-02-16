#!/usr/bin/env python3
"""
Deployment configuration for Movement public fullnode.

This script configures and deploys a public fullnode using the ClusterManager
from the tools package.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Add parent directory to path to import tools
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools import ClusterManager, run_deployment_cli


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parents[1]
CHART_DIR = ROOT_DIR / "charts" / "movement-fullnode"
DEFAULT_CONFIG = ROOT_DIR / "configs" / "testnet.pfn-restore.yaml"


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
    if enable_dns:
        if "DNS_ZONE_NAME" in env_vars:
            variables["dns_zone_name"] = env_vars["DNS_ZONE_NAME"]
        if "FULLNODE_DNS_NAME" in env_vars:
            variables["fullnode_dns_name"] = env_vars["FULLNODE_DNS_NAME"]
    else:
        variables["dns_zone_name"] = ""
        variables["fullnode_dns_name"] = ""
    
    # Bootstrap configuration
    if "BOOTSTRAP_S3_BUCKET" in env_vars:
        variables["fullnode_bootstrap_s3_bucket"] = env_vars["BOOTSTRAP_S3_BUCKET"]
    if "BOOTSTRAP_S3_PREFIX" in env_vars:
        variables["fullnode_bootstrap_s3_prefix"] = env_vars["BOOTSTRAP_S3_PREFIX"]
    if "BOOTSTRAP_S3_REGION" in env_vars:
        variables["fullnode_bootstrap_s3_region"] = env_vars["BOOTSTRAP_S3_REGION"]
    
    # Node configuration
    if "NODE_INSTANCE_TYPES" in env_vars:
        variables["node_instance_types"] = [t.strip() for t in env_vars["NODE_INSTANCE_TYPES"].split(",")]
    
    return variables


def build_helm_config(env_vars: dict, outputs: dict) -> dict:
    """Map environment variables and Terraform outputs to Helm configuration."""
    # Resolve config file
    config_file = Path(env_vars.get("FULLNODE_CONFIG_FILE", str(DEFAULT_CONFIG)))
    if not config_file.is_absolute():
        config_file = ROOT_DIR / config_file
    if not config_file.exists():
        raise RuntimeError(f"Config file not found: {config_file}")
    
    # Get configuration values
    namespace = outputs.get("public_fullnode_namespace", env_vars.get("FULLNODE_NAMESPACE", "movement-l1"))
    release_name = outputs.get("public_fullnode_release_name", "public-fullnode")
    service_name = outputs.get("public_fullnode_service_name", env_vars.get("FULLNODE_SERVICE_NAME", "public-fullnode"))
    
    # Base Helm values
    set_values = {
        "fullnameOverride": service_name,
        "node.id": service_name,
        "storage.create": "true",
        "storage.parameters.type": "gp3",
    }
    
    # Add bootstrap if enabled
    if outputs.get("fullnode_bootstrap_enabled"):
        set_values.update({
            "bootstrap.enabled": "true",
            "bootstrap.s3Uri": outputs["fullnode_bootstrap_s3_uri"],
            "bootstrap.region": outputs["fullnode_bootstrap_region"],
            "serviceAccount.create": "true",
            "serviceAccount.name": outputs["fullnode_service_account_name"],
            "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn": outputs["fullnode_s3_role_arn"],
        })
    else:
        set_values["bootstrap.enabled"] = "false"
    
    return {
        "namespace": namespace,
        "release_name": release_name,
        "service_name": service_name,
        "set_values": set_values,
        "set_files": {"config.inline": config_file},
    }


def deploy(env_vars: dict, force_create: bool, validate: bool) -> None:
    """Deploy infrastructure and workload."""
    cluster = ClusterManager(SCRIPT_DIR, CHART_DIR, ROOT_DIR)
    
    terraform_vars = build_terraform_vars(env_vars)
    outputs = cluster.terraform.get_outputs() or {}
    helm_config = build_helm_config(env_vars, outputs)
    
    cluster.deploy(
        env_vars=env_vars,
        terraform_vars=terraform_vars,
        helm_config=helm_config,
        skip_if_exists=not force_create,
        validate=validate,
    )


def destroy(env_vars: dict) -> None:
    """Destroy infrastructure."""
    cluster = ClusterManager(SCRIPT_DIR, CHART_DIR, ROOT_DIR)
    terraform_vars = build_terraform_vars(env_vars)
    cluster.destroy(terraform_vars)


if __name__ == "__main__":
    sys.exit(run_deployment_cli(deploy, destroy, SCRIPT_DIR / ".env"))