"""Cluster deployment manager - orchestrates Terraform, EKS, and Helm."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .eks import EKSManager
from .helm import HelmManager
from .terraform import TerraformManager
from .utils import info, success, warn
from .validation import validate_deployment


class ClusterManager:
    """Manages complete cluster lifecycle: infrastructure + workload deployment."""

    def __init__(
        self,
        terraform_dir: Path,
        chart_dir: Path,
        root_dir: Path | None = None,
    ):
        """
        Initialize cluster manager.

        Args:
            terraform_dir: Directory containing Terraform configuration
            chart_dir: Directory containing Helm chart
            root_dir: Root directory for resolving relative paths
        """
        self.terraform_dir = terraform_dir
        self.chart_dir = chart_dir
        self.root_dir = root_dir or terraform_dir.parent

        self.terraform = TerraformManager(terraform_dir)

    def deploy(
        self,
        env_vars: dict[str, str],
        terraform_vars: dict[str, Any],
        helm_config: dict[str, Any],
        skip_if_exists: bool = True,
        validate: bool = False,
    ) -> dict[str, Any]:
        """
        Deploy infrastructure and workload.

        Args:
            env_vars: Environment variables
            terraform_vars: Terraform variables to apply
            helm_config: Helm configuration with keys:
                - namespace: Kubernetes namespace
                - release_name: Helm release name
                - service_name: Service name
                - config_file: Path to fullnode config file
                - set_values: Dict of Helm set values
                - set_files: Dict of Helm set-file values
            skip_if_exists: Skip infra creation if cluster exists
            validate: Whether to validate deployment after completion

        Returns:
            Dictionary of deployment information
        """
        # Stage 1: Provision infrastructure
        info("Stage 1/2: Provisioning infrastructure with Terraform")

        outputs = self.terraform.get_outputs()

        # Determine cluster name and region
        cluster_name = (
            outputs.get("cluster_name") or terraform_vars.get("validator_name", "demo") + "-cluster"
        )
        region = outputs.get("region") or terraform_vars.get("region", "us-east-1")

        # Check if cluster exists
        eks = EKSManager(cluster_name, region)
        if skip_if_exists and eks.cluster_exists():
            success(f"Infrastructure already exists (cluster: {cluster_name}, region: {region})")
        else:
            # Provision infrastructure
            self.terraform.init(upgrade=True)
            self.terraform.validate()

            var_args = self.terraform.build_var_args(terraform_vars)
            self.terraform.apply(var_args=var_args, auto_approve=True)
            outputs = self.terraform.get_outputs()

            if not outputs:
                raise RuntimeError("Terraform apply completed but no outputs found")

            success("Infrastructure provisioned successfully")

        # Refresh outputs
        if not outputs:
            outputs = self.terraform.get_outputs()

        # Stage 2: Deploy workload
        info("Stage 2/2: Deploying workload with Helm")

        # Extract configuration with fallbacks
        cluster_name = outputs.get("cluster_name", cluster_name)
        region = outputs.get("region", region)
        namespace = helm_config.get("namespace", "movement-l1")
        release_name = helm_config.get("release_name", "public-fullnode")
        service_name = helm_config.get("service_name", "public-fullnode")

        # Wait for cluster and update kubeconfig
        eks = EKSManager(cluster_name, region)
        eks.wait_until_active()
        eks.update_kubeconfig()

        # Deploy with Helm
        helm = HelmManager(self.chart_dir)
        helm.upgrade_install(
            release_name=release_name,
            namespace=namespace,
            set_values=helm_config.get("set_values", {}),
            set_files=helm_config.get("set_files", {}),
            create_namespace=True,
        )

        # Print deployment information (before validation)
        self._print_deployment_info(
            cluster_name=cluster_name,
            region=region,
            namespace=namespace,
            release_name=release_name,
            service_name=service_name,
            outputs=outputs,
        )

        # Validate deployment (always wait for pod ready, optionally validate API)
        pod_timeout = int(env_vars.get("POD_READY_TIMEOUT", "3600"))
        max_retries = int(env_vars.get("MAX_RETRIES", "60"))
        retry_interval = int(env_vars.get("RETRY_INTERVAL", "10"))

        validate_deployment(
            namespace=namespace,
            service_name=service_name,
            pod_timeout=pod_timeout,
            lb_retries=max_retries,
            interval=retry_interval,
            validate_api=validate,
        )

        success("Deployment completed successfully!")

        return {
            "cluster_name": cluster_name,
            "region": region,
            "namespace": namespace,
            "release_name": release_name,
            "service_name": service_name,
            "outputs": outputs,
        }

    def destroy(self, terraform_vars: dict[str, Any]) -> None:
        """
        Destroy the deployment (Helm + Terraform).

        Args:
            terraform_vars: Terraform variables for destroy
        """
        info("Destroying deployment")

        # Ensure providers are available for terraform output/destroy in clean environments.
        self.terraform.init(upgrade=False)

        outputs = self.terraform.get_outputs()

        if outputs:
            namespace = outputs.get("public_fullnode_namespace", "movement-l1")
            release_name = outputs.get("public_fullnode_release_name", "public-fullnode")
            cluster_name = outputs.get("cluster_name")
            region = outputs.get("region")

            if cluster_name and region:
                eks = EKSManager(cluster_name, region)

                # Update kubeconfig and uninstall Helm release
                try:
                    eks.update_kubeconfig()

                    helm = HelmManager(self.chart_dir)
                    helm.uninstall(release_name, namespace)
                except Exception as e:
                    warn(f"Failed to uninstall Helm release: {e}")

        # Destroy Terraform infrastructure
        var_args = self.terraform.build_var_args(terraform_vars)
        self.terraform.destroy(var_args=var_args, auto_approve=True)

        success("Deployment destroyed successfully")

    def _print_deployment_info(
        self,
        cluster_name: str,
        region: str,
        namespace: str,
        release_name: str,
        service_name: str,
        outputs: dict[str, Any],
    ) -> None:
        """Print deployment information."""
        bootstrap_enabled = outputs.get("fullnode_bootstrap_enabled", False)

        print("\n" + "=" * 80)
        print("📋 Deployment Information:")
        print("=" * 80)
        print(f"Cluster:     {cluster_name}")
        print(f"Region:      {region}")
        print(f"Namespace:   {namespace}")
        print(f"Release:     {release_name}")
        print(f"Service:     {service_name}")
        if bootstrap_enabled:
            print(f"Bootstrap:   Enabled (S3: {outputs.get('fullnode_bootstrap_s3_uri')})")
        print("\n📝 Useful commands:")
        print(f"  kubectl get pods -n {namespace}")
        print(f"  kubectl logs -n {namespace} {service_name}-0 -f")
        if bootstrap_enabled:
            print(f"  kubectl logs -n {namespace} {service_name}-0 -c s3-bootstrap")
        print(f"  kubectl get svc -n {namespace}")
        print("=" * 80 + "\n")
