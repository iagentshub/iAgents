"""Gestión de backend y frontend ejecutados localmente, sin Docker."""

from __future__ import annotations

import hashlib
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
from contextlib import ExitStack
from pathlib import Path

from .common import (
    BACKEND_LOG,
    BACKEND_PID_FILE,
    DATA_DIR,
    ENV_FILE,
    FRONTEND_LOG,
    FRONTEND_PID_FILE,
    IS_WINDOWS,
    LOCAL_DIR,
    REPOS_ROOT,
    SCRIPT_DIR,
    VENV_DIR,
    _npm_cmd,
    read_env_var,
)
from .console import (
    BOLD,
    CYAN,
    GREEN,
    RED,
    RESET,
    YELLOW,
    _confirm_destructive,
    error,
    info,
    success,
    warn,
)


def venv_python() -> Path:
    if IS_WINDOWS:
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def venv_pip() -> Path:
    if IS_WINDOWS:
        return VENV_DIR / "Scripts" / "pip.exe"
    return VENV_DIR / "bin" / "pip"


def ensure_venv() -> None:
    req = (REPOS_ROOT / "backend_fastapi" / "requirements.txt").resolve()
    if not req.is_file():
        error("No se encontró requirements.txt en ../backend_fastapi/")

    if not VENV_DIR.is_dir():
        info("Creando entorno virtual en .venv/ ...")
        subprocess.run([sys.executable, "-m", "venv", str(VENV_DIR)], check=True)

    hash_file = VENV_DIR / ".req_hash"
    cur_hash = hashlib.md5(req.read_bytes()).hexdigest()
    saved_hash = hash_file.read_text().strip() if hash_file.is_file() else ""

    if cur_hash != saved_hash:
        info("Instalando dependencias Python (puede tardar unos minutos)...")
        # Via python -m pip: en Windows pip.exe no puede sobrescribirse a si mismo.
        subprocess.run(
            [str(venv_python()), "-m", "pip", "install", "-q", "--upgrade", "pip"],
            check=True,
        )
        subprocess.run([str(venv_pip()), "install", "-q", "-r", str(req)], check=True)
        hash_file.write_text(cur_hash)
        success("Dependencias instaladas.")


def ensure_frontend_build() -> None:
    frontend_dir = (REPOS_ROOT / "frontend_react").resolve()
    if not (frontend_dir / "package.json").is_file():
        error("No se encontró package.json en ../frontend_react/")
    if not shutil.which("npm"):
        error("Node.js/npm no está instalado. Instálalo desde https://nodejs.org")

    lock_file = frontend_dir / "package-lock.json"
    dist_dir = frontend_dir / "dist"
    hash_file = dist_dir / ".build_hash"
    lock_bytes = lock_file.read_bytes() if lock_file.is_file() else b""
    commit = subprocess.run(
        ["git", "-C", str(frontend_dir), "rev-parse", "HEAD"],
        capture_output=True,
        check=False,
    ).stdout.strip()
    cur_hash = hashlib.md5(lock_bytes + commit).hexdigest()
    saved_hash = hash_file.read_text().strip() if hash_file.is_file() else ""

    if not dist_dir.is_dir() or cur_hash != saved_hash:
        info("Construyendo frontend React (npm ci && npm run build)...")
        subprocess.run(
            _npm_cmd("ci", "--no-audit", "--no-fund"), cwd=frontend_dir, check=True
        )
        subprocess.run(_npm_cmd("run", "build"), cwd=frontend_dir, check=True)
        if cur_hash:
            dist_dir.mkdir(parents=True, exist_ok=True)
            hash_file.write_text(cur_hash)
        success("Frontend React construido en ../frontend_react/dist")


def init_local_data() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    settings_file = DATA_DIR / "settings.json"
    if not settings_file.is_file():
        secret = secrets.token_hex(32)
        settings_file.write_text(f'{{"jwt_secret":"{secret}"}}\n', encoding="utf-8")
        info("settings.json creado con secret aleatorio.")
    info("Directorio de datos listo: ../iagentshub/data/")


def _pid_alive(pid: int) -> bool:
    if IS_WINDOWS:
        out = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _is_running(pidfile: Path) -> bool:
    if not pidfile.is_file():
        return False
    try:
        pid = int(pidfile.read_text().strip())
    except ValueError:
        return False
    return _pid_alive(pid)


def _kill_pid(pidfile: Path) -> bool:
    if not pidfile.is_file():
        return False
    try:
        pid = int(pidfile.read_text().strip())
    except ValueError:
        pidfile.unlink(missing_ok=True)
        return False

    if _pid_alive(pid):
        if IS_WINDOWS:
            subprocess.run(
                ["taskkill", "/PID", str(pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
            # Matar hijos (uvicorn --reload lanza un proceso hijo)
            subprocess.run(
                ["pkill", "-P", str(pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            for _ in range(10):
                if not _pid_alive(pid):
                    break
                time.sleep(0.3)
            if _pid_alive(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
    pidfile.unlink(missing_ok=True)
    return True


def _port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0


def _local_component() -> str:
    component = read_env_var(ENV_FILE, "IAGENTSHUB_COMPONENT", "full")
    if component not in {"full", "backend", "frontend"}:
        error("IAGENTSHUB_COMPONENT debe ser full, backend o frontend.")
    return component


def _local_show_info(
    component: str,
    port: str,
    gaia_port: str,
    admin_email: str,
    backend_url: str,
) -> None:
    print()
    print(f"{BOLD}  ╔══════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}  ║       Modo local (sin Docker)            ║{RESET}")
    print(f"{BOLD}  ╠══════════════════════════════════════════╣{RESET}")
    if component in {"full", "frontend"}:
        print(f"{BOLD}  ║{RESET}  Frontend   › {CYAN}http://localhost:{port}{RESET}")
    if component in {"full", "backend"}:
        print(
            f"{BOLD}  ║{RESET}  Backend    › {CYAN}http://localhost:{gaia_port}{RESET}"
        )
        print(f"{BOLD}  ║{RESET}  Admin      › {CYAN}{admin_email}{RESET}")
        admin_pass_file = DATA_DIR / ".admin_pass"
        if admin_pass_file.is_file():
            admin_pass = admin_pass_file.read_text().strip()
            print(f"{BOLD}  ║{RESET}  Contraseña › {GREEN}{admin_pass}{RESET}")
        else:
            print(
                f"{BOLD}  ║{RESET}  Contraseña › (ver logs: python3 gaia.py logs --local)"
            )
        print(
            f"{BOLD}  ║{RESET}  Base datos › {YELLOW}SQLite — ../iagentshub/data/hub.db{RESET}"
        )
    elif backend_url:
        print(f"{BOLD}  ║{RESET}  API remota › {CYAN}{backend_url}{RESET}")
    print(f"{BOLD}  ╚══════════════════════════════════════════╝{RESET}")
    print()


# ── Comandos modo local ───────────────────────────────────────────────────────


def cmd_local_start() -> None:
    component = _local_component()
    wants_backend = component in {"full", "backend"}
    wants_frontend = component in {"full", "frontend"}
    if (wants_backend and _is_running(BACKEND_PID_FILE)) or (
        wants_frontend and _is_running(FRONTEND_PID_FILE)
    ):
        warn("Los servicios locales ya están en ejecución.")
        cmd_local_status()
        sys.exit(0)

    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    if wants_backend:
        ensure_venv()
        init_local_data()

    port = read_env_var(ENV_FILE, "PORT", "8007")
    try:
        if int(port) < 1024:
            warn(
                f"PORT={port} requiere privilegios en este sistema. Usando 8007 para modo local."
            )
            warn(
                "Añade 'PORT=8007' (u otro puerto >= 1024) en .env para evitar este aviso."
            )
            port = "8007"
    except ValueError:
        pass

    gaia_port = read_env_var(ENV_FILE, "GAIA_PORT", "8765")
    admin_username = read_env_var(ENV_FILE, "GAIA_ADMIN_USERNAME", "admin")
    admin_email = read_env_var(ENV_FILE, "GAIA_ADMIN_EMAIL", "admin@localhost.com")
    admin_reset = read_env_var(ENV_FILE, "GAIA_ADMIN_RESET", "")
    agents_secret = read_env_var(ENV_FILE, "GAIA_AGENTS_SECRET", "")
    registration = read_env_var(ENV_FILE, "GAIA_REGISTRATION", "open")
    cors_origins = read_env_var(
        ENV_FILE, "GAIA_CORS_ORIGINS", f"http://localhost:{port}"
    )
    backend_url = read_env_var(ENV_FILE, "API_BASE", "").rstrip("/")
    if component == "frontend" and not backend_url:
        error(
            "API_BASE debe indicar la URL del backend para arrancar solo el frontend."
        )
    if wants_frontend:
        ensure_frontend_build()
    frontend_dir = (REPOS_ROOT / "frontend_react" / "dist").resolve()

    # ── Comprobación previa de puertos ────────────────────────────────────
    port_conflict = False
    if wants_frontend and _port_in_use(int(port)):
        warn(f"El puerto {port} ya está en uso por otro proceso.")
        warn("El frontend local NO arrancará en ese puerto. Opciones:")
        warn("  • Cambia PORT a otro valor en .env  (p.ej. PORT=8008)")
        warn(
            "  • Detén el proceso que ocupa el puerto y vuelve a ejecutar este comando"
        )
        port_conflict = True
    if wants_backend and _port_in_use(int(gaia_port)):
        warn(f"El puerto {gaia_port} ya está en uso por otro proceso.")
        warn("El backend local NO puede arrancar. Opciones:")
        warn("  • Cambia GAIA_PORT en .env")
        warn(
            "  • Detén el proceso que ocupa el puerto y vuelve a ejecutar este comando"
        )
        error(f"Puerto del backend ({gaia_port}) ocupado. Abortando.")

    # ── Backend ────────────────────────────────────────────────────────────
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if IS_WINDOWS else 0
    if wants_backend:
        info(f"Arrancando backend en puerto {gaia_port} ...")
        backend_dir = (REPOS_ROOT / "backend_fastapi").resolve()
        backend_env = os.environ.copy()
        backend_env.update(
            {
                "GAIA_DATA_DIR": str(DATA_DIR),
                "GAIA_HOST": "0.0.0.0" if component == "backend" else "127.0.0.1",
                "GAIA_PORT": gaia_port,
                "GAIA_RELOAD": "true",
                "GAIA_REGISTRATION": registration,
                "GAIA_ADMIN_USERNAME": admin_username,
                "GAIA_ADMIN_EMAIL": admin_email,
                "GAIA_ADMIN_RESET": admin_reset,
                "GAIA_AGENTS_SECRET": agents_secret,
                "GAIA_CORS_ORIGINS": cors_origins,
                "GAIA_EMAIL_VERIFY": "false",
                "GAIA_SMTP_HOST": "",
                "DATABASE_URL": "",
            }
        )
        with open(BACKEND_LOG, "ab") as log_fh:
            backend_proc = subprocess.Popen(
                [str(venv_python()), "main.py"],
                cwd=str(backend_dir),
                env=backend_env,
                stdout=log_fh,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                creationflags=creationflags,
            )
        BACKEND_PID_FILE.write_text(str(backend_proc.pid))

    # ── Frontend proxy ────────────────────────────────────────────────────
    if wants_frontend and not port_conflict:
        info(f"Arrancando frontend React en puerto {port} ...")
        frontend_env = os.environ.copy()
        frontend_env.update(
            {
                "PORT": port,
                "GAIA_PORT": gaia_port,
                "BACKEND_URL": backend_url,
                "FRONTEND_DIR": str(frontend_dir),
            }
        )
        with open(FRONTEND_LOG, "ab") as log_fh:
            frontend_proc = subprocess.Popen(
                [sys.executable, str(SCRIPT_DIR / "scripts" / "local_proxy.py")],
                env=frontend_env,
                stdout=log_fh,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                creationflags=creationflags,
            )
        FRONTEND_PID_FILE.write_text(str(frontend_proc.pid))
        time.sleep(0.8)
        if not _pid_alive(frontend_proc.pid):
            FRONTEND_PID_FILE.unlink(missing_ok=True)
            warn("El proxy del frontend no pudo arrancar. Revisa el log:")
            warn(f"  {FRONTEND_LOG}")

    success("Servicios locales arrancados.")
    _local_show_info(component, port, gaia_port, admin_email, backend_url)
    if port_conflict:
        warn(f"ATENCIÓN: el frontend usa el puerto {port} ocupado por otro proceso.")
        warn(f"Accede directamente al backend › http://localhost:{gaia_port}")
    info(
        "Logs → python3 gaia.py logs --local   |   Para detener → python3 gaia.py stop --local"
    )


def cmd_local_stop() -> None:
    stopped = False
    if _kill_pid(BACKEND_PID_FILE):
        info("Backend detenido.")
        stopped = True
    if _kill_pid(FRONTEND_PID_FILE):
        info("Frontend detenido.")
        stopped = True
    if stopped:
        success("Servicios locales detenidos.")
    else:
        info("No había servicios locales en ejecución.")


def cmd_local_restart() -> None:
    cmd_local_stop()
    cmd_local_start()


def cmd_local_status() -> None:
    print()
    for svc, pidfile in (
        ("backend", BACKEND_PID_FILE),
        ("frontend", FRONTEND_PID_FILE),
    ):
        if pidfile.is_file():
            pid = pidfile.read_text().strip()
            if pid.isdigit() and _pid_alive(int(pid)):
                print(f"  {GREEN}●{RESET} {svc} (PID {pid}) — en ejecución")
            else:
                print(f"  {RED}●{RESET} {svc} (PID {pid}) — detenido (PID obsoleto)")
                pidfile.unlink(missing_ok=True)
        else:
            print(f"  {RED}●{RESET} {svc} — no iniciado")
    print()


def cmd_local_reset(yes: bool) -> None:
    component = _local_component()
    if component in {"full", "backend"}:
        _confirm_destructive("el directorio de datos local (../iagentshub/data/)", yes)
    cmd_local_stop()
    if component in {"full", "backend"} and DATA_DIR.exists():
        shutil.rmtree(DATA_DIR)
        info("Directorio de datos eliminado.")
    success("Reinstalando desde cero...")
    cmd_local_start()


def cmd_local_logs() -> None:
    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    BACKEND_LOG.touch(exist_ok=True)
    FRONTEND_LOG.touch(exist_ok=True)
    info("Mostrando logs (Ctrl+C para salir)...")

    with ExitStack() as stack:
        handles = {}
        for label, path in (("backend", BACKEND_LOG), ("frontend", FRONTEND_LOG)):
            fh = stack.enter_context(open(path, encoding="utf-8", errors="replace"))
            fh.seek(0, os.SEEK_END)
            handles[label] = fh

        try:
            while True:
                progressed = False
                for label, fh in handles.items():
                    line = fh.readline()
                    while line:
                        sys.stdout.write(f"[{label}] {line}")
                        progressed = True
                        line = fh.readline()
                if not progressed:
                    time.sleep(0.3)
        except KeyboardInterrupt:
            pass
