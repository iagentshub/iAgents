"""Parseo de argumentos y enrutado de comandos de gaia.py."""

from __future__ import annotations

import os
import shutil
import sys

from .build_push import cmd_push
from .common import IAGENTS_DIR
from .compose import (
    cmd_logs,
    cmd_reset,
    cmd_restart,
    cmd_start,
    cmd_status,
    cmd_stop,
    cmd_update,
)
from .console import BOLD, RESET, YELLOW, error, warn
from .local_process import (
    cmd_local_logs,
    cmd_local_reset,
    cmd_local_restart,
    cmd_local_start,
    cmd_local_status,
    cmd_local_stop,
)


def _print_local_usage() -> None:
    print(f"{BOLD}Uso:{RESET} python3 gaia.py <comando> --local")
    print()
    print("  start    Arranca backend (uvicorn) y frontend (proxy Python) sin Docker")
    print("  stop     Detiene los servicios locales")
    print("  restart  Detiene y vuelve a arrancar los servicios locales")
    print("  logs     Muestra los logs en tiempo real")
    print("  status   Estado de los procesos locales")
    print("  reset    Borra iAgents/data/ (BD y config) y reinstala desde cero")
    print("           Pide escribir RESET para confirmar; no se puede omitir")
    print()
    print(
        f"  {YELLOW}Base de datos: SQLite en iAgents/data/hub.db  (con persistencia){RESET}"
    )
    print(f"  {YELLOW}Sin PostgreSQL ni contenedores Docker.{RESET}")
    print(f"  {YELLOW}Frontend React servido desde ../frontend_react/dist.{RESET}")
    print()


def _print_docker_usage() -> None:
    print(f"{BOLD}Uso:{RESET} python3 gaia.py <comando> [--dev] [--hub] [--local]")
    print()
    print("  start    Arranca los servicios")
    print("  stop     Detiene los servicios")
    print(
        "  restart  Detiene y vuelve a arrancar los servicios (sin descargar nada nuevo)"
    )
    print("  logs     Muestra los logs en tiempo real")
    print("  update   Actualiza a la última versión y reinicia")
    print("  status   Estado de los contenedores")
    print(
        "  push     Construye imágenes y las sube a GHCR  (requiere --hub o sin flag)"
    )
    print("  reset    Borra la BD y TODOS los volúmenes, y reinstala desde cero")
    print("           Pide escribir RESET para confirmar; no se puede omitir")
    print()
    print(f"{BOLD}Flags:{RESET}")
    print(
        "  --dev              Usa repos locales (../backend_fastapi, ../frontend_react) con hot reload"
    )
    print(
        "  --hub              Usa imágenes pre-construidas de GHCR (despliegue rápido)"
    )
    print(
        "  --local            Sin Docker: uvicorn + proxy Python (SQLite, sin PostgreSQL)"
    )
    print("  Base de datos Docker: PostgreSQL (predeterminada)")
    print()
    print(f"{BOLD}Flujo recomendado para despliegues rápidos (--hub):{RESET}")
    print(
        "  1. En tu máquina:   python3 gaia.py push              # construye y sube imágenes"
    )
    print(
        "  2. En el servidor:  python3 gaia.py start --hub       # descarga y arranca"
    )
    print("  3. Para actualizar: python3 gaia.py update --hub      # pull + reinicio")
    print()


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    dev = local = hub = help_mode = False
    positional: list[str] = []

    for arg in sys.argv[1:]:
        if arg == "--dev":
            dev = True
        elif arg == "--local":
            local = True
        elif arg == "--hub":
            hub = True
        elif arg in ("-h", "--help", "help"):
            help_mode = True
        else:
            positional.append(arg)

    if dev and local:
        error("--dev y --local son incompatibles.")
    if dev and hub:
        error("--dev y --hub son incompatibles.")
    if local and hub:
        error("--local y --hub son incompatibles.")

    command = positional[0] if positional else ""

    # El arranque sin flags prefiere Docker. Si ni siquiera está instalado,
    # usa el modo local SQLite; un daemon instalado pero detenido sigue siendo
    # un error para no abrir una base local vacía por accidente.
    if command == "start" and not (dev or local or hub) and not shutil.which("docker"):
        warn("Docker no está instalado; arrancando en modo local con SQLite.")
        local = True

    if local:
        if help_mode or not command:
            _print_local_usage()
            sys.exit(0 if help_mode else 1)
        if command == "start":
            cmd_local_start()
        elif command == "stop":
            cmd_local_stop()
        elif command == "restart":
            cmd_local_restart()
        elif command == "logs":
            cmd_local_logs()
        elif command == "status":
            cmd_local_status()
        elif command == "reset":
            cmd_local_reset()
        else:
            error(
                f"Comando desconocido: {command}. Usa: python3 gaia.py --help --local"
            )
        return

    if dev:
        compose = [
            "docker",
            "compose",
            "-f",
            "docker-compose.yml",
            "-f",
            "docker-compose.dev.yml",
        ]
    elif hub:
        compose = ["docker", "compose", "-f", "docker-compose.hub.yml"]
    else:
        compose = ["docker", "compose"]

    os.chdir(IAGENTS_DIR)

    if help_mode or not command:
        _print_docker_usage()
        sys.exit(0 if help_mode else 1)

    if command == "start":
        cmd_start(compose, dev, hub)
    elif command == "stop":
        cmd_stop(compose)
    elif command == "restart":
        cmd_restart(compose, dev, hub)
    elif command == "logs":
        cmd_logs(compose)
    elif command == "update":
        cmd_update(compose, dev, hub)
    elif command == "status":
        cmd_status(compose)
    elif command == "push":
        cmd_push()
    elif command == "reset":
        cmd_reset(compose, dev, hub)
    else:
        error(f"Comando desconocido: {command}. Usa: python3 gaia.py --help")
