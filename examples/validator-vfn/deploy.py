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

# Add parent directory to path to import tools
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools import ClusterManager, HelmManager, error, info, run_deployment_cli, success

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parents[1]
CHART_DIR = ROOT_DIR / "charts" / "movement-node"


def create_validator_secret_from_aws_sm(
    namespace: str,
    secret_name: str,
    aws_secret_name: str,
    region: str,
    profile: str | None = None,
) -> None:
    """Create Kubernetes secret from AWS Secrets Manager.

    Args:
        namespace: Kubernetes namespace
        secret_name: Name for the Kubernetes secret
        aws_secret_name: AWS Secrets Manager secret name
        region: AWS region
        profile: AWS profile to use (optional)
    """
    try:
        import boto3
        from kubernetes import client, config

        info(f"Reading validator identity from AWS Secrets Manager: {aws_secret_name}")

        # Read from AWS Secrets Manager
        if profile:
            session = boto3.Session(profile_name=profile)
            sm_client = session.client("secretsmanager", region_name=region)
        else:
            sm_client = boto3.client("secretsmanager", region_name=region)
        response = sm_client.get_secret_value(SecretId=aws_secret_name)
        secret_data = response["SecretString"]

        # Connect to Kubernetes
        config.load_kube_config()
        v1 = client.CoreV1Api()

        # Check if secret already exists
        try:
            v1.read_namespaced_secret(secret_name, namespace)
            info(f"  Secret '{secret_name}' already exists in namespace '{namespace}'")
            return
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise

        # Create Kubernetes secret using string_data (no base64 encoding needed)
        k8s_secret = client.V1Secret(
            metadata=client.V1ObjectMeta(name=secret_name),
            string_data={"validator-identity.yaml": secret_data},
            type="Opaque",
        )

        v1.create_namespaced_secret(namespace, k8s_secret)
        success(f"✅ Created Kubernetes secret '{secret_name}' from AWS Secrets Manager")

    except Exception as e:
        error(f"Failed to create secret from AWS Secrets Manager: {e}")
        raise


def build_terraform_vars(env_vars: dict) -> dict:
    """Map environment variables to Terraform variables."""
    variables = {}

    validator_name = env_vars.get("VALIDATOR_NAME", "validator-01")
    variables["validator_name"] = validator_name
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
        variables["node_instance_types"] = [
            t.strip() for t in env_vars["NODE_INSTANCE_TYPES"].split(",")
        ]

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
    variables["tags"] = {"Validator": validator_name}

    return variables


def deploy_node(
    helm,
    node_type: str,
    node_name: str,
    namespace: str,
    validator_name: str,
    service_type: str | None = None,
    validator_service: str | None = None,
    vfn_service: str | None = None,
    validator_keys_secret: str | None = None,
) -> None:
    """Deploy a single node with appropriate configuration."""
    info(f"Deploying {node_type}: {node_name}")

    # Base configuration with S3 bootstrap for all nodes
    set_values = {
        "node.type": node_type,
        "node.name": node_name,
        "network.name": "testnet",
        "network.chainId": "250",
        "storage.create": "true" if node_type == "validator" else "false",
        "storage.storageClassName": "gp3",
        "storage.parameters.type": "gp3",
        "storage.parameters.iops": "6000",
        "storage.parameters.throughput": "500",
        # Enable S3 bootstrap for all nodes
        "bootstrap.enabled": "true",
        "bootstrap.s3.bucket": "movement-2026-02-11-backup",
        "bootstrap.s3.prefix": "testnet/db",
        "bootstrap.s3.region": "us-west-2",
        "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type": "nlb",
        "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme": "internet-facing",
        "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-additional-resource-tags": f"Validator={validator_name}",
        "storage.parameters.tagSpecification_1": f"Validator={validator_name}",
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

    helm.upgrade_install(
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
    # Check if validator should be public (for cross-cluster validator communication)
    validator_public = env_vars.get("VALIDATOR_PUBLIC", "false").lower() in ("true", "1", "yes")
    validator_service_type = "LoadBalancer" if validator_public else "ClusterIP"

    # Display deployment plan
    info("Deployment Topology:")
    validator_access = "LoadBalancer - public" if validator_public else "ClusterIP - private"
    info(f"  Validator: {validator_name} ({validator_access})")
    if deploy_vfn and deploy_fullnode:
        info(f"  VFN: {vfn_name} (ClusterIP - private)")
        info(f"  Fullnode: {fullnode_name} (LoadBalancer - public)")
        info("  → 3-tier setup: External clients access fullnode")
    elif deploy_vfn:
        info(f"  VFN: {vfn_name} (LoadBalancer - public)")
        info("  → 2-tier setup: External clients access VFN")
    else:
        validator_note = "Public for P2P" if validator_public else "No public access"
        info(f"  → Validator-only setup: {validator_note}")

    # Step 1: Provision infrastructure
    terraform_vars = build_terraform_vars(env_vars)
    outputs = cluster.terraform.get_outputs() or {}

    if not force_create and outputs:
        info("Infrastructure already exists, skipping Terraform")
    else:
        cluster.terraform.init(upgrade=True)
        cluster.terraform.validate()
        var_args = cluster.terraform.build_var_args(terraform_vars)
        cluster.terraform.apply(var_args=var_args, auto_approve=True)
        outputs = cluster.terraform.get_outputs()

    # Update kubeconfig
    cluster_name = outputs.get(
        "cluster_name", f"{env_vars.get('VALIDATOR_NAME', 'validator')}-cluster"
    )
    region = outputs.get("region", env_vars.get("AWS_REGION", "us-east-1"))

    from tools.eks import EKSManager

    profile = env_vars.get("AWS_PROFILE")
    eks = EKSManager(cluster_name, region, profile)
    eks.wait_until_active()
    eks.update_kubeconfig()

    # Step 1.5: Create validator secret from AWS Secrets Manager (if configured)
    aws_secret_name = env_vars.get("VALIDATOR_KEYS_SECRET_NAME", "")
    if aws_secret_name:
        info("\n" + "=" * 80)
        info("Creating Kubernetes Secret from AWS Secrets Manager")
        info("=" * 80)
        create_validator_secret_from_aws_sm(
            namespace=namespace,
            secret_name=validator_keys_secret,
            aws_secret_name=aws_secret_name,
            region=region,
            profile=profile,
        )
    else:
        info(f"Skipping AWS Secrets Manager (using existing K8s secret: {validator_keys_secret})")

    # Step 2: Deploy nodes in order
    from tools.helm import HelmManager

    helm = HelmManager(CHART_DIR)

    # Deploy validator first (ClusterIP or LoadBalancer based on config)
    deploy_node(
        helm=helm,
        node_type="validator",
        node_name=validator_name,
        namespace=namespace,
        validator_name=validator_name,
        service_type=validator_service_type,
        validator_keys_secret=validator_keys_secret,
    )

    # Deploy VFN if requested
    if deploy_vfn:
        # VFN service type depends on whether fullnode is deployed
        vfn_service_type = "ClusterIP" if deploy_fullnode else "LoadBalancer"

        deploy_node(
            helm=helm,
            node_type="vfn",
            node_name=vfn_name,
            namespace=namespace,
            validator_name=validator_name,
            service_type=vfn_service_type,
            validator_service=validator_name,
        )

    # Deploy fullnode if requested
    if deploy_fullnode:
        deploy_node(
            helm=helm,
            node_type="fullnode",
            node_name=fullnode_name,
            namespace=namespace,
            validator_name=validator_name,
            service_type="LoadBalancer",
            vfn_service=vfn_name if deploy_vfn else None,
        )

    # Step 3: Validation (if requested)
    if validate:
        from tools.validation import validate_deployment, wait_for_pods_ready

        info("\n" + "=" * 80)
        info("Validating All Nodes")
        info("=" * 80)

        # Build list of all deployed pods
        pods_to_check = [validator_name]
        if deploy_vfn:
            pods_to_check.append(vfn_name)
        if deploy_fullnode:
            pods_to_check.append(fullnode_name)

        # Wait for all pods and check their API health
        wait_for_pods_ready(
            namespace=namespace,
            pod_names=pods_to_check,
            timeout=3600,
            check_api_health=True,
        )

        # Final validation: check public endpoint if available
        if deploy_fullnode or deploy_vfn:
            validate_service = fullnode_name if deploy_fullnode else vfn_name

            info(f"\nValidating public endpoint: {validate_service}")
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
        info("\n🌐 Public Access: Fullnode LoadBalancer")
        info(f"   Service: {fullnode_name}")
        info(f"   kubectl get svc {fullnode_name} -n {namespace}")
    elif deploy_vfn:
        info("\n🌐 Public Access: VFN LoadBalancer")
        info(f"   Service: {vfn_name}")
        info(f"   kubectl get svc {vfn_name} -n {namespace}")

    info("\n📊 Check pod status:")
    info(f"   kubectl get pods -n {namespace}")

    info("\n📝 View logs:")
    info(f"   kubectl logs {validator_name}-0 -n {namespace}")
    if deploy_vfn:
        info(f"   kubectl logs {vfn_name}-0 -n {namespace}")
    if deploy_fullnode:
        info(f"   kubectl logs {fullnode_name}-0 -n {namespace}")
    info("=" * 80 + "\n")

    return True


def destroy(env_vars: dict) -> None:
    """Destroy all deployed resources."""
    cluster = ClusterManager(SCRIPT_DIR, CHART_DIR, ROOT_DIR)
    helm = HelmManager(CHART_DIR)

    namespace = env_vars.get("NAMESPACE", "movement-l1")
    validator_name = env_vars.get("VALIDATOR_NAME", "validator-01")
    vfn_name = env_vars.get("VFN_NAME", "vfn-01")
    fullnode_name = env_vars.get("FULLNODE_NAME", "fullnode-01")
    deploy_vfn = env_vars.get("DEPLOY_VFN", "true").lower() in ("true", "1", "yes")
    deploy_fullnode = env_vars.get("DEPLOY_FULLNODE", "false").lower() in ("true", "1", "yes")

    # Uninstall Helm releases in reverse order
    if deploy_fullnode:
        helm.uninstall(fullnode_name, namespace)
    if deploy_vfn:
        helm.uninstall(vfn_name, namespace)
    helm.uninstall(validator_name, namespace)

    # Destroy Terraform infrastructure
    terraform_vars = build_terraform_vars(env_vars)
    cluster.destroy(terraform_vars)


if __name__ == "__main__":
    sys.exit(run_deployment_cli(deploy, destroy, SCRIPT_DIR / ".env"))
