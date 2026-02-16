"""Common utility functions for deployment tools."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional


def info(msg: str) -> None:
    """Print info message."""
    print(f"\n{'='*80}")
    print(f"[INFO] {msg}")
    print(f"{'='*80}\n")


def success(msg: str) -> None:
    """Print success message."""
    print(f"\n✅ {msg}\n")


def warn(msg: str) -> None:
    """Print warning message."""
    print(f"\n⚠️  [WARN] {msg}\n")


def error(msg: str) -> None:
    """Print error message."""
    print(f"\n❌ ERROR: {msg}\n", file=sys.stderr)


def fail(msg: str) -> None:
    """Print error and exit."""
    error(msg)
    sys.exit(1)


def run_command(
    cmd: List[str],
    *,
    cwd: Optional[Path] = None,
    capture: bool = False,
    check: bool = True,
    env: Optional[Dict[str, str]] = None,
    verbose: bool = True,
) -> subprocess.CompletedProcess[str]:
    """
    Run a shell command.
    
    Args:
        cmd: Command and arguments as a list
        cwd: Working directory for the command
        capture: Whether to capture output
        check: Whether to raise exception on non-zero exit
        env: Additional environment variables
        verbose: Whether to print the command being run
    
    Returns:
        CompletedProcess with the result
        
    Raises:
        RuntimeError: If check=True and command fails
    """
    if verbose:
        print(f"→ Running: {' '.join(cmd)}")
    
    cmd_env = os.environ.copy()
    if env:
        cmd_env.update(env)
    
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=capture,
        env=cmd_env,
    )
    
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        fail(f"Command failed: {' '.join(cmd)}\n{detail}")
    
    return proc


def load_env_file(env_file: Path) -> Dict[str, str]:
    """
    Load environment variables from a .env file.
    
    Args:
        env_file: Path to the .env file
        
    Returns:
        Dictionary of environment variables
        
    Raises:
        SystemExit: If file doesn't exist
    """
    if not env_file.exists():
        fail(f"Environment file not found: {env_file}")
    
    env_vars = {}
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip().strip('"\'')
    
    return env_vars


def bool_env(name: str, default: bool = False) -> bool:
    """
    Get boolean value from environment variable.
    
    Args:
        name: Environment variable name
        default: Default value if not set
        
    Returns:
        Boolean value
    """
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}