"""Comandos de ciclo de vida para los despliegues con Docker Compose."""

from __future__ import annotations

import os
import subprocess
import time

from .common import (
    ENV_FILE,
    check_docker,
    ensure_env,
    get_port,
    inject_github_token,
    read_env_var,
    run_ok,
)
from .console import (
    BOLD,
    CYAN,
    GREEN,
    RESET,
    _confirm_destructive,
    info,
    success,
)


def _show_admin_info(compose: list[str], hub: bool = False) -> None:
    # docker-compose.hub.yml (imagen unificada) llama al servicio "iagentshub";
    # docker-compose.yml (backend+frontend separados) lo llama "backend".
    service = "iagentshub" if hub else "backend"
    for _ in range(30):
        if run_ok(compose + ["exec", "-T", service, "sh", "-c", "exit 0"]):
            break
        time.sleep(1)

    admin_email = subprocess.run(
        compose
        + ["exec", "-T", service, "sh", "-c", 'printf "%s" "$GAIA_ADMIN_EMAIL"'],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    if not admin_email:
        return

    admin_pass = subprocess.run(
        compose
        + [
            "exec",
            "-T",
            service,
            "sh",
            "-c",
            'cat "$GAIA_DATA_DIR/.admin_pass" 2>/dev/null',
        ],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()

    port = get_port()
    gaia_port = read_env_var(ENV_FILE, "GAIA_PORT", "8765")

    print()
    print(f"{BOLD}  ╔══════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}  ║       Acceso de administrador            ║{RESET}")
    print(f"{BOLD}  ╠══════════════════════════════════════════╣{RESET}")
    print(f"{BOLD}  ║{RESET}  Frontend   › {CYAN}http://localhost:{port}{RESET}")
    print(f"{BOLD}  ║{RESET}  Backend    › {CYAN}http://localhost:{gaia_port}{RESET}")
    print(f"{BOLD}  ║{RESET}  Email      › {CYAN}{admin_email}{RESET}")
    if admin_pass:
        print(f"{BOLD}  ║{RESET}  Contraseña › {GREEN}{admin_pass}{RESET}")
    else:
        print(f"{BOLD}  ║{RESET}  Contraseña › (sin cambios)")
    print(f"{BOLD}  ╚══════════════════════════════════════════╝{RESET}")
    print()


def cmd_start(compose: list[str], dev: bool, hub: bool) -> None:
    check_docker()
    ensure_env()
    env = os.environ.copy()
    inject_github_token(env)
    if dev:
        info("Modo desarrollo — usando repos locales")
    if hub:
        info("Modo Hub — usando imágenes de GitHub Container Registry")
        info("Descargando imágenes actualizadas...")
        subprocess.run(compose + ["pull"], env=env, check=True)
    info("Construyendo e iniciando servicios...")
    subprocess.run(
        compose + ["rm", "-f", "data-init"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if hub:
        subprocess.run(compose + ["up", "-d"], env=env, check=True)
    else:
        subprocess.run(compose + ["up", "-d", "--build"], env=env, check=True)
    print()
    success(f"iAgents Hub en marcha → http://localhost:{get_port()}")
    _show_admin_info(compose, hub)


def cmd_stop(compose: list[str]) -> None:
    check_docker()
    info("Deteniendo servicios...")
    subprocess.run(compose + ["down"], check=True)
    success("Servicios detenidos.")


def cmd_restart(compose: list[str], dev: bool, hub: bool) -> None:
    cmd_stop(compose)
    cmd_start(compose, dev, hub)


def cmd_logs(compose: list[str]) -> None:
    check_docker()
    info("Mostrando logs (Ctrl+C para salir)...")
    try:
        subprocess.run(compose + ["logs", "-f", "--tail=100"], check=False)
    except KeyboardInterrupt:
        pass


def cmd_update(compose: list[str], dev: bool, hub: bool) -> None:
    check_docker()
    ensure_env()
    env = os.environ.copy()
    inject_github_token(env)
    if dev:
        info("Modo desarrollo — usando repos locales")
    if hub:
        info(
            "Modo Hub — descargando imágenes actualizadas de GitHub Container Registry"
        )
    info("Actualizando a la última versión...")
    subprocess.run(
        compose + ["rm", "-f", "data-init"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(compose + ["down"], env=env, check=True)
    if hub:
        subprocess.run(compose + ["pull"], env=env, check=True)
        subprocess.run(compose + ["up", "-d"], env=env, check=True)
    else:
        subprocess.run(compose + ["up", "-d", "--build"], env=env, check=True)
    print()
    success(f"Actualización completada → http://localhost:{get_port()}")
    _show_admin_info(compose, hub)


def cmd_status(compose: list[str]) -> None:
    check_docker()
    subprocess.run(compose + ["ps"], check=False)


def cmd_reset(compose: list[str], dev: bool, hub: bool, yes: bool) -> None:
    check_docker()
    ensure_env()
    _confirm_destructive(
        "los volúmenes Docker (base de datos, código clonado por code-sync)", yes
    )
    env = os.environ.copy()
    inject_github_token(env)
    info("Eliminando contenedores y volúmenes...")
    subprocess.run(compose + ["down", "-v"], env=env, check=True)
    success("Volúmenes eliminados. Reinstalando desde cero...")
    cmd_start(compose, dev, hub)
