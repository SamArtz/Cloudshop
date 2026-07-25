#!/usr/bin/env python3
"""
Empaqueta Lambdas en terraform/.build/<servicio>/ para archive_file.

Uso:
  python scripts/stage_lambda.py auth_service
  python scripts/stage_lambda.py all
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "terraform" / ".build"

SERVICES: dict[str, dict] = {
    "auth_service": {
        "src": ROOT / "src" / "auth_service",
        "files": ["handler.py", "auth_utils.py", "permissions.py", "repository.py"],
        "shared": True,
        "reqs": ["PyJWT>=2.8.0", "bcrypt>=4.1.0"],
    },
    "authorizer": {
        "src": ROOT / "src" / "authorizer",
        "files": ["handler.py"],
        "shared": False,
        "reqs": ["PyJWT>=2.8.0"],
    },
    "catalog_service": {
        "src": ROOT / "src" / "catalog_service",
        "files": ["handler.py", "permissions.py", "repository.py"],
        "shared": True,
        "reqs": [],
    },
    "order_service": {
        "src": ROOT / "src" / "order_service",
        "files": ["handler.py", "permissions.py", "repository.py"],
        "shared": True,
        "reqs": [],
    },
    "notifications": {
        "src": ROOT / "src" / "notifications",
        "files": ["handler.py"],
        "shared": False,
        "reqs": [],
    },
}


def _pip_install(target: Path, reqs: list[str]) -> None:
    if not reqs:
        return
    req_file = target / "requirements.pkg.txt"
    req_file.write_text("\n".join(reqs) + "\n", encoding="utf-8")
    cmd = [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--platform",
        "manylinux2014_x86_64",
        "--target",
        str(target),
        "--implementation",
        "cp",
        "--python-version",
        "3.12",
        "--only-binary=:all:",
        "--upgrade",
        "-r",
        str(req_file),
    ]
    subprocess.check_call(cmd)


def stage(name: str) -> Path:
    if name not in SERVICES:
        raise SystemExit(f"Servicio desconocido: {name}. Opciones: {', '.join(SERVICES)}")

    cfg = SERVICES[name]
    dst = BUILD / name
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)

    for fname in cfg["files"]:
        src = cfg["src"] / fname
        if not src.exists():
            raise FileNotFoundError(src)
        shutil.copy2(src, dst / fname)

    if cfg["shared"]:
        shared_src = ROOT / "src" / "shared"
        shutil.copytree(shared_src, dst / "shared")

    _pip_install(dst, cfg["reqs"])
    print(f"OK: staged {dst}")
    return dst


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    arg = sys.argv[1]
    names = list(SERVICES) if arg == "all" else [arg]
    for name in names:
        stage(name)


if __name__ == "__main__":
    main()
