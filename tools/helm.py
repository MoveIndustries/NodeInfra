"""Helm chart deployment manager."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .utils import info, run_command, success


class HelmManager:
    """Manages Helm chart deployments."""

    def __init__(self, chart_dir: Path):
        """
        Initialize Helm manager.

        Args:
            chart_dir: Path to Helm chart directory
        """
        self.chart_dir = chart_dir

    def upgrade_install(
        self,
        release_name: str,
        namespace: str,
        values: dict[str, Any] | None = None,
        set_values: dict[str, str] | None = None,
        set_files: dict[str, Path] | None = None,
        create_namespace: bool = True,
        reset_values: bool = False,
        wait: bool = False,
        timeout: str = "5m",
    ) -> None:
        """
        Install or upgrade a Helm release.

        Args:
            release_name: Name of the Helm release
            namespace: Kubernetes namespace
            values: Dictionary of values to pass (will be converted to --set)
            set_values: Dictionary of simple key=value pairs to set
            set_files: Dictionary of key=filepath pairs to set from file
            create_namespace: Whether to create namespace if it doesn't exist
            reset_values: Whether to reset to chart defaults before applying values
            wait: Whether to wait for resources to be ready
            timeout: Timeout for wait operation
        """
        info(f"Deploying Helm release '{release_name}' to namespace '{namespace}'")

        cmd = [
            "helm",
            "upgrade",
            "--install",
            release_name,
            str(self.chart_dir),
            "--namespace",
            namespace,
        ]

        if create_namespace:
            cmd.append("--create-namespace")

        if reset_values:
            cmd.append("--reset-values")

        if wait:
            cmd.extend(["--wait", "--timeout", timeout])

        # Add set values
        if set_values:
            for key, value in set_values.items():
                cmd.extend(["--set", f"{key}={value}"])

        # Add set-file values
        if set_files:
            for key, file_path in set_files.items():
                cmd.extend(["--set-file", f"{key}={file_path}"])

        # Add values from dictionary
        if values:
            for key, value in values.items():
                if isinstance(value, bool):
                    value_str = "true" if value else "false"
                else:
                    value_str = str(value)
                cmd.extend(["--set", f"{key}={value_str}"])

        run_command(cmd)
        success(f"Helm release '{release_name}' deployed successfully")

    def uninstall(
        self,
        release_name: str,
        namespace: str,
        wait: bool = False,
        timeout: str = "5m",
    ) -> None:
        """
        Uninstall a Helm release.

        Args:
            release_name: Name of the Helm release
            namespace: Kubernetes namespace
            wait: Whether to wait for resources to be deleted
            timeout: Timeout for wait operation
        """
        info(f"Uninstalling Helm release '{release_name}' from namespace '{namespace}'")

        cmd = [
            "helm",
            "uninstall",
            release_name,
            "--namespace",
            namespace,
        ]

        if wait:
            cmd.extend(["--wait", "--timeout", timeout])

        run_command(cmd, check=False)  # Don't fail if release doesn't exist
        success(f"Helm release '{release_name}' uninstalled")

    def list_releases(self, namespace: str | None = None) -> None:
        """
        List Helm releases.

        Args:
            namespace: Optional namespace to filter releases
        """
        cmd = ["helm", "list"]
        if namespace:
            cmd.extend(["--namespace", namespace])

        run_command(cmd)
