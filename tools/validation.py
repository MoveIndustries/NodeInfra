"""Kubernetes workload validation utilities."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

from .utils import info, warn, fail


def load_k8s_client(kubeconfig_path: Optional[Path] = None):
    """
    Load Kubernetes client.
    
    Args:
        kubeconfig_path: Optional path to kubeconfig file
        
    Returns:
        CoreV1Api client instance
    """
    try:
        from kubernetes import client, config
    except ImportError:
        fail("Missing dependency 'kubernetes'. Install with: pip install kubernetes")
    
    if kubeconfig_path:
        config.load_kube_config(config_file=str(kubeconfig_path))
    else:
        config.load_kube_config()
    
    return client.CoreV1Api()


def wait_for_pod_ready(
    namespace: str,
    app_label: str,
    timeout: int = 3600,
    interval: int = 10,
    kubeconfig_path: Optional[Path] = None,
) -> None:
    """
    Wait for a pod with specified app label to become ready.
    
    Args:
        namespace: Kubernetes namespace
        app_label: Value of the app label
        timeout: Maximum time to wait in seconds
        interval: Check interval in seconds
        kubeconfig_path: Optional path to kubeconfig
        
    Raises:
        SystemExit: If timeout or pod fails to become ready
    """
    core_api = load_k8s_client(kubeconfig_path)
    deadline = time.time() + timeout
    selector = f"app={app_label}"
    
    info(f"Waiting for pod to become ready (namespace={namespace}, app={app_label})")
    
    while time.time() < deadline:
        pods = core_api.list_namespaced_pod(namespace=namespace, label_selector=selector).items
        
        if not pods:
            warn(f"No pods found with label app={app_label}")
            time.sleep(interval)
            continue
        
        for pod in pods:
            pod_name = pod.metadata.name
            phase = pod.status.phase
            
            # Check if pod is ready
            for cond in (pod.status.conditions or []):
                if cond.type == "Ready" and cond.status == "True":
                    info(f"✅ Pod {pod_name} is ready")
                    return
            
            # Show pod status
            print(f"  Pod {pod_name}: phase={phase}")
            
            # Check for failed state
            if phase == "Failed":
                fail(f"Pod {pod_name} entered Failed state")
        
        time.sleep(interval)
    
    fail(f"Timeout waiting for pod to become ready (namespace={namespace}, app={app_label})")


def wait_for_loadbalancer_and_api(
    namespace: str,
    service_name: str,
    api_path: str = "/v1",
    api_port: int = 8080,
    retries: int = 60,
    interval: int = 10,
    kubeconfig_path: Optional[Path] = None,
) -> str:
    """
    Wait for LoadBalancer to get external IP and API to be healthy.
    
    Args:
        namespace: Kubernetes namespace
        service_name: Service name
        api_path: API path to check (default: /v1)
        api_port: API port (default: 8080)
        retries: Number of retries
        interval: Interval between retries in seconds
        kubeconfig_path: Optional path to kubeconfig
        
    Returns:
        LoadBalancer hostname or IP
        
    Raises:
        SystemExit: If timeout or API fails health check
    """
    core_api = load_k8s_client(kubeconfig_path)
    
    info(f"Waiting for LoadBalancer and API health (service={service_name})")
    
    for attempt in range(1, retries + 1):
        try:
            svc = core_api.read_namespaced_service(name=service_name, namespace=namespace)
        except Exception as e:
            warn(f"Failed to read service: {e}, retry {attempt}/{retries}")
            time.sleep(interval)
            continue
        
        ingress = (svc.status.load_balancer.ingress or []) if svc.status and svc.status.load_balancer else []
        host = ""
        if ingress:
            host = (ingress[0].hostname or ingress[0].ip or "").strip()
        
        if host:
            url = f"http://{host}:{api_port}{api_path}"
            try:
                with urllib.request.urlopen(url, timeout=10) as resp:
                    body = resp.read().decode("utf-8", errors="replace")
                    if resp.status == 200:
                        payload = json.loads(body)
                        ledger_version = str(payload.get("ledger_version", ""))
                        if ledger_version.isdigit():
                            info(f"✅ API healthy at {host} (ledger_version={ledger_version})")
                            return host
            except urllib.error.HTTPError as e:
                warn(f"LB reachable, API HTTP {e.code}, retry {attempt}/{retries}")
            except Exception as e:
                warn(f"LB/API not ready ({str(e)}), retry {attempt}/{retries}")
        else:
            print(f"  LoadBalancer pending, retry {attempt}/{retries}")
        
        time.sleep(interval)
    
    fail("Timeout waiting for LoadBalancer/API readiness")


def validate_deployment(
    namespace: str,
    service_name: str,
    pod_timeout: int = 3600,
    lb_retries: int = 60,
    interval: int = 10,
    validate_api: bool = True,
    kubeconfig_path: Optional[Path] = None,
) -> None:
    """
    Validate that a deployment is healthy.
    
    Args:
        namespace: Kubernetes namespace
        service_name: Service name (also used as app label)
        pod_timeout: Timeout for pod readiness in seconds
        lb_retries: Number of retries for LoadBalancer check
        interval: Check interval in seconds
        validate_api: Whether to validate LoadBalancer and API health (default: True)
        kubeconfig_path: Optional path to kubeconfig
        
    Raises:
        SystemExit: If validation fails
    """
    info("Validating deployment")
    
    # Wait for pod to be ready
    wait_for_pod_ready(
        namespace=namespace,
        app_label=service_name,
        timeout=pod_timeout,
        interval=interval,
        kubeconfig_path=kubeconfig_path
    )
    
    # Optionally wait for LoadBalancer and API health
    if validate_api:
        wait_for_loadbalancer_and_api(
            namespace=namespace,
            service_name=service_name,
            retries=lb_retries,
            interval=interval,
            kubeconfig_path=kubeconfig_path
        )
    
    info("✅ Deployment validation passed")
