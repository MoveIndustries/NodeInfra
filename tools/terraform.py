"""Terraform operations manager."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .utils import fail, info, run_command, success, warn


class TerraformManager:
    """Manages Terraform operations for infrastructure provisioning."""

    def __init__(self, working_dir: Path):
        """
        Initialize Terraform manager.

        Args:
            working_dir: Directory containing Terraform configuration
        """
        self.working_dir = working_dir
        if not self.working_dir.exists():
            fail(f"Terraform directory not found: {working_dir}")

    def init(self, upgrade: bool = True) -> None:
        """
        Initialize Terraform.

        Args:
            upgrade: Whether to upgrade providers
        """
        info("Initializing Terraform")
        cmd = ["terraform", "init"]
        if upgrade:
            cmd.append("-upgrade")
        run_command(cmd, cwd=self.working_dir)
        success("Terraform initialized")

    def validate(self) -> None:
        """Validate Terraform configuration."""
        info("Validating Terraform configuration")
        run_command(["terraform", "validate"], cwd=self.working_dir)
        success("Terraform configuration is valid")

    def plan(self, var_args: list[str] | None = None, out_file: Path | None = None) -> None:
        """
        Run Terraform plan.

        Args:
            var_args: Variable arguments to pass to Terraform
            out_file: Optional output file for the plan
        """
        info("Planning Terraform changes")
        cmd = ["terraform", "plan"]
        if var_args:
            cmd.extend(var_args)
        if out_file:
            cmd.extend(["-out", str(out_file)])
        run_command(cmd, cwd=self.working_dir)

    def apply(
        self,
        var_args: list[str] | None = None,
        plan_file: Path | None = None,
        auto_approve: bool = True,
    ) -> None:
        """
        Apply Terraform configuration.

        Args:
            var_args: Variable arguments to pass to Terraform
            plan_file: Optional plan file to apply
            auto_approve: Whether to auto-approve changes
        """
        info("Applying Terraform configuration")
        cmd = ["terraform", "apply"]

        if plan_file:
            cmd.append(str(plan_file))
        else:
            if auto_approve:
                cmd.append("-auto-approve")
            if var_args:
                cmd.extend(var_args)

        run_command(cmd, cwd=self.working_dir)
        success("Terraform applied successfully")

    def destroy(self, var_args: list[str] | None = None, auto_approve: bool = True) -> None:
        """
        Destroy Terraform-managed infrastructure.

        Args:
            var_args: Variable arguments to pass to Terraform
            auto_approve: Whether to auto-approve destruction
        """
        info("Destroying Terraform infrastructure")
        cmd = ["terraform", "destroy"]
        if auto_approve:
            cmd.append("-auto-approve")
        if var_args:
            cmd.extend(var_args)
        run_command(cmd, cwd=self.working_dir)
        success("Terraform destroyed successfully")

    def get_outputs(self) -> dict[str, Any]:
        """
        Get Terraform outputs.

        Returns:
            Dictionary of output values
        """
        proc = run_command(
            ["terraform", "output", "-json"],
            cwd=self.working_dir,
            capture=True,
            check=False,
            verbose=False,
        )

        if proc.returncode != 0:
            return {}

        text = (proc.stdout or "").strip()
        if not text:
            return {}

        try:
            raw = json.loads(text)
            outputs = {}
            for key, value in raw.items():
                if isinstance(value, dict) and "value" in value:
                    outputs[key] = value["value"]
            return outputs
        except json.JSONDecodeError:
            warn("Failed to parse Terraform outputs")
            return {}

    def get_output(self, key: str, raw: bool = False) -> str | None:
        """
        Get a single Terraform output value.

        Args:
            key: Output key name
            raw: Whether to get raw output

        Returns:
            Output value or None if not found
        """
        cmd = ["terraform", "output"]
        if raw:
            cmd.append("-raw")
        cmd.append(key)

        proc = run_command(cmd, cwd=self.working_dir, capture=True, check=False, verbose=False)

        if proc.returncode != 0:
            return None

        return (proc.stdout or "").strip()

    def build_var_args(self, variables: dict[str, Any]) -> list[str]:
        """
        Build Terraform variable arguments.

        Args:
            variables: Dictionary of variables

        Returns:
            List of -var arguments
        """
        var_args = []
        for key, value in variables.items():
            if value is None:
                continue
            if isinstance(value, bool):
                value = "true" if value else "false"
            elif isinstance(value, list | dict):
                value = json.dumps(value)
            var_args.extend(["-var", f"{key}={value}"])
        return var_args
