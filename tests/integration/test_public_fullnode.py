#!/usr/bin/env python3
"""Integration test for public fullnode deployment.

This test validates the complete deployment process by calling the deployment
script and ensuring it completes successfully with validation enabled.

The test uses the .env file in examples/public-fullnode/ for configuration,
which can be overridden with environment variables.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Add parent directory to path to import tools
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools import info, success

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE_DIR = ROOT / "examples" / "public-fullnode"
DEPLOY_SCRIPT = EXAMPLE_DIR / "deploy.py"


def main() -> int:
    """Run the integration test."""
    info("Public fullnode integration test")
    info(f"Using deployment script: {DEPLOY_SCRIPT}")

    # Set AWS configuration
    os.environ["AWS_SDK_LOAD_CONFIG"] = "1"

    # Build command to run deploy script
    cmd = [sys.executable, str(DEPLOY_SCRIPT)]

    # Use .env file from example directory
    env_file = EXAMPLE_DIR / ".env"
    if env_file.exists():
        cmd.extend(["--env-file", str(env_file)])

    # Enable validation
    cmd.append("--validate")

    # Run deployment with validation
    info(f"Running: {' '.join(cmd)}")
    import subprocess

    result = subprocess.run(cmd)

    if result.returncode != 0:
        raise RuntimeError(f"Deployment failed with exit code {result.returncode}")

    success("Integration test passed!")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}")
        sys.exit(1)
