from __future__ import annotations

import os
import socket
from pathlib import Path
from typing import Any

from fastapi import FastAPI

try:
    import pwd
except ImportError:  # pragma: no cover - fallback para ambientes sem modulo pwd.
    pwd = None  # type: ignore[assignment]


APP_NAME = "kubernetes-security-hardening-lab-app"
APP_VERSION = "1.0.0"
APP_OBJECTIVE = (
    "Aplicacao didatica para demonstrar seguranca de workloads Kubernetes "
    "via ServiceAccount, securityContext e permissoes de filesystem."
)

SERVICE_ACCOUNT_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"

app = FastAPI(title=APP_NAME, version=APP_VERSION)


def _get_uid() -> int | None:
    return os.getuid() if hasattr(os, "getuid") else None


def _get_gid() -> int | None:
    return os.getgid() if hasattr(os, "getgid") else None


def _get_groups() -> list[int]:
    if hasattr(os, "getgroups"):
        return list(os.getgroups())
    return []


def _get_effective_user() -> str:
    if not hasattr(os, "geteuid"):
        return "indisponivel"

    euid = os.geteuid()
    if pwd is None:
        return str(euid)

    try:
        return pwd.getpwuid(euid).pw_name
    except KeyError:
        return str(euid)


def _read_proc_status_subset() -> dict[str, str]:
    proc_path = Path("/proc/self/status")
    if not proc_path.exists():
        return {"error": "/proc/self/status nao encontrado"}

    wanted_keys = {
        "Name",
        "State",
        "Uid",
        "Gid",
        "Groups",
        "NoNewPrivs",
        "Seccomp",
        "CapInh",
        "CapPrm",
        "CapEff",
        "CapBnd",
        "CapAmb",
    }

    selected: dict[str, str] = {}
    for line in proc_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in wanted_keys:
            selected[key] = value.strip()
    return selected


def _try_write(path: Path) -> dict[str, Any]:
    payload = "write-test from kubernetes-security-hardening-lab\n"
    try:
        with path.open("w", encoding="utf-8") as file:
            file.write(payload)
        return {"path": str(path), "success": True}
    except Exception as exc:  # noqa: BLE001
        return {
            "path": str(path),
            "success": False,
            "error_type": type(exc).__name__,
            "error": str(exc),
        }


@app.get("/")
def root() -> dict[str, str]:
    return {
        "project": APP_NAME,
        "objective": APP_OBJECTIVE,
        "version": APP_VERSION,
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.get("/security")
def security() -> dict[str, Any]:
    token_exists = Path(SERVICE_ACCOUNT_TOKEN_PATH).exists()
    return {
        "uid": _get_uid(),
        "gid": _get_gid(),
        "groups": _get_groups(),
        "hostname": socket.gethostname(),
        "service_account_token_mounted": token_exists,
        "service_account_token_path": SERVICE_ACCOUNT_TOKEN_PATH,
        "proc_self_status": _read_proc_status_subset(),
        "effective_user": _get_effective_user(),
        "cwd": os.getcwd(),
    }


@app.get("/write-test")
def write_test() -> dict[str, Any]:
    paths = [
        Path("/data/write-test.txt"),
        Path("/tmp/tmp-test.txt"),
        Path("/app/blocked-test.txt"),
    ]
    results = [_try_write(path) for path in paths]
    return {
        "results": results,
        "success_count": sum(1 for item in results if item["success"]),
        "failure_count": sum(1 for item in results if not item["success"]),
    }
