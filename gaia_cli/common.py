"""Configuración compartida y helpers de entorno y procesos externos."""

from __future__ import annotations

import os
import secrets
import shutil
import subprocess
from pathlib import Path

from .console import IS_WINDOWS, error, info, warn

SCRIPT_DIR = Path(__file__).resolve().parent.parent
IAGENTS_DIR = SCRIPT_DIR
REPOS_ROOT = IAGENTS_DIR.parent

LOCAL_DIR = IAGENTS_DIR / ".gaia-local"
BACKEND_PID_FILE = LOCAL_DIR / "backend.pid"
FRONTEND_PID_FILE = LOCAL_DIR / "frontend.pid"
BACKEND_LOG = LOCAL_DIR / "backend.log"
FRONTEND_LOG = LOCAL_DIR / "frontend.log"
VENV_DIR = IAGENTS_DIR / ".venv"
DATA_DIR = REPOS_ROOT / "iagentshub" / "data"
ENV_FILE = IAGENTS_DIR / ".env"


def read_env_var(env_path: Path, key: str, default: str = "") -> str:
    if not env_path.is_file():
        return default
    for line in env_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1].strip().strip('"')
    return default


def _rand_hex() -> str:
    return secrets.token_hex(32)


# ── Helpers de ejecución de comandos externos ─────────────────────────────────


def _npm_cmd(*args: str) -> list[str]:
    # npm en Windows es un shim .cmd — CreateProcess no lo resuelve sin pasar
    # por cmd.exe, a diferencia de docker/git que son ejecutables reales.
    if IS_WINDOWS:
        return ["cmd", "/c", "npm", *args]
    return ["npm", *args]


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=False, **kwargs)


def run_ok(cmd: list[str], **kwargs) -> bool:
    try:
        return (
            subprocess.run(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                **kwargs,
            ).returncode
            == 0
        )
    except FileNotFoundError:
        return False


# ── Helpers Docker ────────────────────────────────────────────────────────────


def check_docker() -> None:
    if not shutil.which("docker"):
        error(
            "Docker no está instalado. Descárgalo en https://docs.docker.com/get-docker/"
        )
    if not run_ok(["docker", "info"]):
        error("Docker no está en ejecución. Árrancalo e inténtalo de nuevo.")


def ensure_env() -> None:
    env_example = IAGENTS_DIR / ".env.example"

    if not ENV_FILE.is_file():
        if not env_example.is_file():
            error(f"No se encontró .env.example en {IAGENTS_DIR}")
        content = env_example.read_text(encoding="utf-8")
        agents_secret = _rand_hex()
        db_pass = _rand_hex()
        lines = []
        for line in content.splitlines(keepends=True):
            if line.startswith("GAIA_AGENTS_SECRET="):
                lines.append(f"GAIA_AGENTS_SECRET={agents_secret}\n")
            elif line.startswith("GAIA_DB_PASSWORD="):
                lines.append(f"GAIA_DB_PASSWORD={db_pass}\n")
            else:
                lines.append(line)
        ENV_FILE.write_text("".join(lines), encoding="utf-8")
        warn("Se ha creado .env con secrets aleatorios.")
        warn(
            "Revisa GAIA_FRONTEND_URL y GAIA_ADMIN_EMAIL si vas a desplegar en producción."
        )
        print()
        return

    # .env ya existe: asegurar que GAIA_DB_PASSWORD tiene un valor no vacío/débil
    cur_pass = read_env_var(ENV_FILE, "GAIA_DB_PASSWORD")
    if not cur_pass or cur_pass == "changeme":
        db_pass = _rand_hex()
        lines = ENV_FILE.read_text(encoding="utf-8").splitlines(keepends=True)
        found = False
        for i, line in enumerate(lines):
            if line.startswith("GAIA_DB_PASSWORD="):
                lines[i] = f"GAIA_DB_PASSWORD={db_pass}\n"
                found = True
                break
        if not found:
            lines.append(f"GAIA_DB_PASSWORD={db_pass}\n")
        ENV_FILE.write_text("".join(lines), encoding="utf-8")
        info("GAIA_DB_PASSWORD actualizado con valor aleatorio en .env")


def get_port() -> str:
    return read_env_var(ENV_FILE, "PORT", "80")


def inject_github_token(env: dict) -> None:
    token = os.environ.get("GITHUB_TOKEN") or read_env_var(ENV_FILE, "GITHUB_TOKEN")
    if not token:
        return
    for key in ("BACKEND_REPO", "FRONTEND_REPO", "SKILLS_REPO", "AGENTS_REPO"):
        repo = read_env_var(ENV_FILE, key)
        if repo:
            env[key] = repo.replace("https://", f"https://{token}@", 1)
