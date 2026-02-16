"""AWS EKS cluster management."""

from __future__ import annotations

import time
from typing import Optional

from .utils import info, success, warn, run_command, fail


class EKSManager:
    """Manages AWS EKS cluster operations."""
    
    def __init__(self, cluster_name: str, region: str):
        """
        Initialize EKS manager.
        
        Args:
            cluster_name: Name of the EKS cluster
            region: AWS region
        """
        self.cluster_name = cluster_name
        self.region = region
    
    def cluster_exists(self) -> bool:
        """
        Check if EKS cluster exists.
        
        Returns:
            True if cluster exists, False otherwise
        """
        proc = run_command(
            [
                "aws", "eks", "describe-cluster",
                "--region", self.region,
                "--name", self.cluster_name
            ],
            capture=True,
            check=False,
            verbose=False
        )
        
        if proc.returncode == 0:
            return True
        
        err = (proc.stderr or "").strip()
        if "ResourceNotFoundException" in err:
            return False
        
        fail(f"Unable to check EKS cluster status: {err or 'unknown error'}")
        return False
    
    def get_cluster_status(self) -> Optional[str]:
        """
        Get cluster status.
        
        Returns:
            Cluster status (ACTIVE, CREATING, DELETING, etc.) or None if not found
        """
        proc = run_command(
            [
                "aws", "eks", "describe-cluster",
                "--region", self.region,
                "--name", self.cluster_name,
                "--query", "cluster.status",
                "--output", "text"
            ],
            capture=True,
            check=False,
            verbose=False
        )
        
        if proc.returncode != 0:
            return None
        
        return (proc.stdout or "").strip()
    
    def wait_until_active(self, timeout: int = 1800, interval: int = 15) -> None:
        """
        Wait for cluster to become ACTIVE.
        
        Args:
            timeout: Maximum time to wait in seconds
            interval: Check interval in seconds
            
        Raises:
            SystemExit: If timeout or cluster enters terminal state
        """
        info(f"Waiting for EKS cluster to become ACTIVE (timeout: {timeout}s)")
        deadline = time.time() + timeout
        
        while time.time() < deadline:
            status = self.get_cluster_status()
            
            if status == "ACTIVE":
                success(f"Cluster {self.cluster_name} is ACTIVE")
                return
            
            if status in {"FAILED", "DELETING"}:
                fail(f"Cluster entered terminal state: {status}")
            
            print(f"  Cluster status: {status} (waiting...)")
            time.sleep(interval)
        
        fail(f"Timeout waiting for cluster {self.cluster_name} to become ACTIVE")
    
    def update_kubeconfig(self, kubeconfig_path: Optional[str] = None) -> None:
        """
        Update kubeconfig for the cluster.
        
        Args:
            kubeconfig_path: Optional path to kubeconfig file
        """
        info(f"Updating kubeconfig for cluster {self.cluster_name}")
        cmd = [
            "aws", "eks", "update-kubeconfig",
            "--region", self.region,
            "--name", self.cluster_name
        ]
        
        if kubeconfig_path:
            cmd.extend(["--kubeconfig", kubeconfig_path])
        
        run_command(cmd)
        success("Kubeconfig updated successfully")