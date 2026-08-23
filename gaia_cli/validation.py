"""Validación estructural de todos los despliegues Docker Compose."""

from __future__ import annotations

import os
import subprocess

from .common import IAGENTS_DIR, check_docker_cli, ensure_env

_COMPOSES = (
    ("docker-compose.yml", ("-f", "docker-compose.yml"), False),
    ("docker-compose.backend.yml", ("-f", "docker-compose.backend.yml"), False),
    (
        "dev.yml (sobre el base)",
        ("-f", "docker-compose.yml", "-f", "docker-compose.dev.yml"),
        False,
    ),
    ("docker-compose.frontend.yml", ("-f", "docker-compose.frontend.yml"), True),
    ("docker-compose.hub.yml", ("-f", "docker-compose.hub.yml"), True),
)


def cmd_validate() -> None:
    """Prepara el entorno real y valida los cinco Compose sin arrancarlos."""
    check_docker_cli()
    ensure_env()
    fallos = 0

    for etiqueta, archivos, necesita_relleno in _COMPOSES:
        env = os.environ.copy()
        if necesita_relleno:
            # Solo permiten expandir la estructura; no se arranca ningún servicio.
            env["API_BASE"] = "http://localhost:8765"
            env["WATCHTOWER_HTTP_API_TOKEN"] = "relleno"

        result = subprocess.run(
            ["docker", "compose", *archivos, "config"],
            cwd=IAGENTS_DIR,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            print(f"  ok    {etiqueta}")
            continue

        fallos += 1
        print(f"  FALLA {etiqueta}")
        salida = (result.stderr or result.stdout).rstrip()
        if salida:
            print("\n".join(f"        {line}" for line in salida.splitlines()))

    if fallos:
        print(f"composes con errores: {fallos}")
        raise SystemExit(1)
    print("los 5 composes validan")
