"""Command-line interface utilities for deployment scripts."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Callable, Dict, Any

from .utils import load_env_file


def create_deployment_cli(
    script_name: str = "deploy.py",
    default_env_file: Path = Path(".env"),
) -> argparse.ArgumentParser:
    """
    Create standard argument parser for deployment scripts.
    
    Args:
        script_name: Name of the script for help text
        default_env_file: Default path to .env file
        
    Returns:
        Configured ArgumentParser
    """
    parser = argparse.ArgumentParser(
        description=f"Deploy infrastructure using {script_name}",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Deploy using .env file
  python3 deploy.py

  # Deploy with validation
  python3 deploy.py --validate

  # Destroy deployment
  python3 deploy.py --destroy

For more information, see README.md
        """
    )
    
    parser.add_argument(
        "--env-file",
        type=Path,
        default=default_env_file,
        help=f"Path to environment file (default: {default_env_file})"
    )
    parser.add_argument(
        "--destroy",
        action="store_true",
        help="Destroy the deployment"
    )
    parser.add_argument(
        "--force-create",
        action="store_true",
        help="Force infrastructure creation even if cluster exists"
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate deployment (wait for pod ready and API health)"
    )
    
    return parser


def setup_aws_environment(env_vars: Dict[str, str]) -> None:
    """
    Configure AWS environment from loaded variables.
    
    Args:
        env_vars: Environment variables dictionary
    """
    if "AWS_PROFILE" in env_vars:
        os.environ["AWS_PROFILE"] = env_vars["AWS_PROFILE"]
    if "AWS_REGION" in env_vars:
        os.environ["AWS_REGION"] = env_vars["AWS_REGION"]
        os.environ["AWS_DEFAULT_REGION"] = env_vars["AWS_REGION"]
    os.environ["AWS_SDK_LOAD_CONFIG"] = "1"


def run_deployment_cli(
    deploy_fn: Callable[[Dict[str, str], bool, bool], None],
    destroy_fn: Callable[[Dict[str, str]], None],
    default_env_file: Path = Path(".env"),
) -> int:
    """
    Run standard deployment CLI workflow.
    
    Args:
        deploy_fn: Function to call for deployment
            Signature: deploy_fn(env_vars, force_create, validate)
        destroy_fn: Function to call for destruction
            Signature: destroy_fn(env_vars)
        default_env_file: Default path to .env file
        
    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    parser = create_deployment_cli(default_env_file=default_env_file)
    args = parser.parse_args()
    
    try:
        # Load environment variables
        env_vars = load_env_file(args.env_file)
        
        # Setup AWS environment
        setup_aws_environment(env_vars)
        
        # Run deployment or destroy
        if args.destroy:
            destroy_fn(env_vars)
        else:
            deploy_fn(env_vars, args.force_create, args.validate)
        
        return 0
    
    except KeyboardInterrupt:
        print("\n\n⚠️  Operation interrupted by user")
        return 130
    except Exception as exc:
        print(f"\n❌ ERROR: {exc}", file=sys.stderr)
        return 1