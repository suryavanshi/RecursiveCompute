"""Run the local Verilator regression flow on Modal.

Usage:
    modal run infra/modal/run_verilator.py --target local-regress

The remote job uses CPU-only Modal workers, installs Verilator and build tools,
copies the repository into the image, and runs an internal `local-*` make target
inside the container. The public Makefile targets dispatch here by default.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import modal


REMOTE_ROOT = Path("/workspace/RecursiveCompute")


def local_repo_root() -> Path:
    candidate = Path(__file__).resolve()
    for parent in candidate.parents:
        if (parent / "README.md").exists() and (parent / "rtl").exists():
            return parent
    raise RuntimeError("could not locate local repository root")


def ignore_repo_path(path: Path) -> bool:
    ignored_dirs = {".git", "__pycache__", "build", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
    if any(part in ignored_dirs for part in path.parts):
        return True
    if path.suffix in {".pyc", ".pdf"}:
        return True
    return False


image = modal.Image.debian_slim(python_version="3.12").apt_install("make", "g++", "verilator")
if modal.is_local():
    image = image.add_local_dir(local_repo_root(), remote_path=str(REMOTE_ROOT), ignore=ignore_repo_path)

app = modal.App("recursivecompute-verilator")

ALLOWED_TARGETS = {
    "local-test",
    "local-lint",
    "local-verilate",
    "local-sim",
    "local-regress",
}


@app.function(
    image=image,
    timeout=60 * 30,
    cpu=2.0,
    memory=4096,
)
def run_target(target: str) -> str:
    if target not in ALLOWED_TARGETS:
        allowed = ", ".join(sorted(ALLOWED_TARGETS))
        raise ValueError(f"unsupported target {target!r}; allowed targets: {allowed}")
    completed = subprocess.run(
        ["make", target],
        cwd=REMOTE_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout)
    return completed.stdout


@app.local_entrypoint()
def main(target: str = "local-regress") -> None:
    print(run_target.remote(target))
