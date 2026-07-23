#!/usr/bin/env python3
"""gaia.py — gestión de iAgents Hub (reemplaza a gaia.sh / gaia.bat).

Vive en la raíz de iAgents/ (junto a .env, data/, docker-compose*.yml) — se
ejecuta como `python3 gaia.py <comando>`. local_proxy.py vive en scripts/.

Uso: python3 gaia.py <comando> [--dev] [--hub] [--local] [--frontend=<var>]

  start    Arranca los servicios
  stop     Detiene los servicios
  logs     Muestra los logs en tiempo real
  update   Actualiza a la última versión y reinicia  (solo Docker)
  status   Estado de los servicios
  push     Construye las imágenes Docker y las sube a Docker Hub  (solo --hub)

Flags:
  --dev              Docker con repos locales (../backend_fastapi, ../frontend_vanilla) — hot reload
  --hub              Docker con imágenes pre-construidas de Docker Hub   — producción rápida
  --local            Sin Docker: uvicorn + proxy Python (SQLite, sin PostgreSQL)
  --frontend=<var>   Limita 'push' a una variante: vanilla|react (default: sube ambas)

Un único script, sin dependencias externas (solo librería estándar), para no
tener que mantener lógica duplicada entre bash (gaia.sh) y batch (gaia.bat).
"""

from __future__ import annotations

import hashlib
import os
import platform
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
# iAgents/ (.env, data/, .venv, docker/, docker-compose*.yml, scripts/ viven aquí)
IAGENTS_DIR = SCRIPT_DIR
# all_iagenthub/ (backend_fastapi, frontend_vanilla, frontend_react son hermanos de iAgents/)
REPOS_ROOT = IAGENTS_DIR.parent
IS_WINDOWS = platform.system() == "Windows"

# ── Colores ────────────────────────────────────────────────────────────────
_USE_COLOR = sys.stdout.isatty()


def _c(code: str) -> str:
    return code if _USE_COLOR else ""


RED = _c("\033[0;31m")
GREEN = _c("\033[0;32m")
YELLOW = _c("\033[1;33m")
CYAN = _c("\033[0;36m")
BOLD = _c("\033[1m")
RESET = _c("\033[0m")


def info(msg: str) -> None:
    print(f"{CYAN}{BOLD}[gaia]{RESET} {msg}")


def success(msg: str) -> None:
    print(f"{GREEN}{BOLD}[gaia]{RESET} {msg}")


def warn(msg: str) -> None:
    print(f"{YELLOW}{BOLD}[gaia]{RESET} {msg}")


def error(msg: str) -> "None":
    print(f"{RED}{BOLD}[gaia]{RESET} {msg}", file=sys.stderr)
    sys.exit(1)


# ── Rutas modo local ─────────────────────────────────────────────────────────
LOCAL_DIR = IAGENTS_DIR / ".gaia-local"
BACKEND_PID_FILE = LOCAL_DIR / "backend.pid"
FRONTEND_PID_FILE = LOCAL_DIR / "frontend.pid"
BACKEND_LOG = LOCAL_DIR / "backend.log"
FRONTEND_LOG = LOCAL_DIR / "frontend.log"
VENV_DIR = IAGENTS_DIR / ".venv"
# Mismo directorio que usa backend_fastapi/app/config/data.py por defecto (sin
# GAIA_DATA_DIR): REPOS_ROOT/iagentshub/data, hermano de backend_fastapi/.
DATA_DIR = REPOS_ROOT / "iagentshub" / "data"
ENV_FILE = IAGENTS_DIR / ".env"


def venv_python() -> Path:
    if IS_WINDOWS:
        return VENV_DIR / "Scripts" / "python.exe"
    return VENV_DIR / "bin" / "python"


def venv_pip() -> Path:
    if IS_WINDOWS:
        return VENV_DIR / "Scripts" / "pip.exe"
    return VENV_DIR / "bin" / "pip"


# ── Helpers de fichero .env ───────────────────────────────────────────────────


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
    return subprocess.run(cmd, **kwargs)


def run_ok(cmd: list[str], **kwargs) -> bool:
    try:
        return (
            subprocess.run(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                **kwargs,
            ).returncode
            == 0
        )
    except FileNotFoundError:
        return False


# ── Helpers Docker ────────────────────────────────────────────────────────────


def check_docker() -> None:
    if not shutil.which("docker"):
        error("Docker no está instalado. Descárgalo en https://docs.docker.com/get-docker/")
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
        warn("Revisa GAIA_FRONTEND_URL y GAIA_ADMIN_EMAIL si vas a desplegar en producción.")
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


def _show_admin_info(compose: list[str]) -> None:
    for _ in range(30):
        if run_ok(compose + ["exec", "-T", "backend", "sh", "-c", "exit 0"]):
            break
        time.sleep(1)

    admin_email = subprocess.run(
        compose + ["exec", "-T", "backend", "sh", "-c", 'printf "%s" "$GAIA_ADMIN_EMAIL"'],
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not admin_email:
        return

    admin_pass = subprocess.run(
        compose + ["exec", "-T", "backend", "sh", "-c", 'cat "$GAIA_DATA_DIR/.admin_pass" 2>/dev/null'],
        capture_output=True,
        text=True,
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


# ── Helpers modo local ────────────────────────────────────────────────────────


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
        subprocess.run([str(venv_pip()), "install", "-q", "--upgrade", "pip"], check=True)
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
    cur_hash = hashlib.md5(lock_file.read_bytes()).hexdigest() if lock_file.is_file() else ""
    saved_hash = hash_file.read_text().strip() if hash_file.is_file() else ""

    if not dist_dir.is_dir() or cur_hash != saved_hash:
        info("Construyendo frontend React (npm ci && npm run build)...")
        subprocess.run(_npm_cmd("ci", "--no-audit", "--no-fund"), cwd=frontend_dir, check=True)
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
        settings_file.write_text('{"jwt_secret":"%s"}\n' % secret, encoding="utf-8")
        info("settings.json creado con secret aleatorio.")
    info("Directorio de datos listo: ../iagentshub/data/")


def _pid_alive(pid: int) -> bool:
    if IS_WINDOWS:
        out = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            capture_output=True,
            text=True,
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


def _local_show_info(port: str, gaia_port: str, admin_email: str) -> None:
    print()
    print(f"{BOLD}  ╔══════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}  ║       Modo local (sin Docker)            ║{RESET}")
    print(f"{BOLD}  ╠══════════════════════════════════════════╣{RESET}")
    print(f"{BOLD}  ║{RESET}  Frontend   › {CYAN}http://localhost:{port}{RESET}")
    print(f"{BOLD}  ║{RESET}  Backend    › {CYAN}http://localhost:{gaia_port}{RESET}")
    print(f"{BOLD}  ║{RESET}  Admin      › {CYAN}{admin_email}{RESET}")
    admin_pass_file = DATA_DIR / ".admin_pass"
    if admin_pass_file.is_file():
        admin_pass = admin_pass_file.read_text().strip()
        print(f"{BOLD}  ║{RESET}  Contraseña › {GREEN}{admin_pass}{RESET}")
    else:
        print(f"{BOLD}  ║{RESET}  Contraseña › (ver logs: python3 gaia.py logs --local)")
    print(f"{BOLD}  ║{RESET}  Base datos › {YELLOW}SQLite — ../iagentshub/data/hub.db{RESET}")
    print(f"{BOLD}  ╚══════════════════════════════════════════╝{RESET}")
    print()


# ── Comandos modo local ───────────────────────────────────────────────────────


def cmd_local_start(_frontend_arg: str | None) -> None:
    if _is_running(BACKEND_PID_FILE) or _is_running(FRONTEND_PID_FILE):
        warn("Los servicios locales ya están en ejecución.")
        cmd_local_status()
        sys.exit(0)

    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    ensure_venv()
    init_local_data()

    port = read_env_var(ENV_FILE, "PORT", "8007")
    try:
        if int(port) < 1024:
            warn(f"PORT={port} requiere privilegios en este sistema. Usando 8007 para modo local.")
            warn("Añade 'PORT=8007' (u otro puerto >= 1024) en .env para evitar este aviso.")
            port = "8007"
    except ValueError:
        pass

    gaia_port = read_env_var(ENV_FILE, "GAIA_PORT", "8765")
    admin_email = read_env_var(ENV_FILE, "GAIA_ADMIN_EMAIL", "admin@localhost")
    admin_reset = read_env_var(ENV_FILE, "GAIA_ADMIN_RESET", "")
    agents_secret = read_env_var(ENV_FILE, "GAIA_AGENTS_SECRET", "")
    registration = read_env_var(ENV_FILE, "GAIA_REGISTRATION", "open")
    cors_origins = read_env_var(ENV_FILE, "GAIA_CORS_ORIGINS", f"http://localhost:{port}")
    frontend_variant = read_env_var(ENV_FILE, "GAIA_FRONTEND_VARIANT", "vanilla")

    if frontend_variant == "react":
        ensure_frontend_build()
        frontend_dir = (REPOS_ROOT / "frontend_react" / "dist").resolve()
    else:
        frontend_dir = (REPOS_ROOT / "frontend_vanilla").resolve()

    # ── Comprobación previa de puertos ────────────────────────────────────
    port_conflict = False
    if _port_in_use(int(port)):
        warn(f"El puerto {port} ya está en uso por otro proceso.")
        warn("El frontend local NO arrancará en ese puerto. Opciones:")
        warn("  • Cambia PORT a otro valor en .env  (p.ej. PORT=8008)")
        warn("  • Detén el proceso que ocupa el puerto y vuelve a ejecutar este comando")
        port_conflict = True
    if _port_in_use(int(gaia_port)):
        warn(f"El puerto {gaia_port} ya está en uso por otro proceso.")
        warn("El backend local NO puede arrancar. Opciones:")
        warn("  • Cambia GAIA_PORT en .env")
        warn("  • Detén el proceso que ocupa el puerto y vuelve a ejecutar este comando")
        error(f"Puerto del backend ({gaia_port}) ocupado. Abortando.")

    # ── Backend ────────────────────────────────────────────────────────────
    info(f"Arrancando backend en puerto {gaia_port} ...")
    backend_dir = (REPOS_ROOT / "backend_fastapi").resolve()
    backend_env = os.environ.copy()
    backend_env.update(
        {
            "GAIA_DATA_DIR": str(DATA_DIR),
            "GAIA_HOST": "127.0.0.1",
            "GAIA_PORT": gaia_port,
            "GAIA_RELOAD": "true",
            "GAIA_REGISTRATION": registration,
            "GAIA_ADMIN_EMAIL": admin_email,
            "GAIA_ADMIN_RESET": admin_reset,
            "GAIA_AGENTS_SECRET": agents_secret,
            "GAIA_CORS_ORIGINS": cors_origins,
            "GAIA_EMAIL_VERIFY": "false",
            "GAIA_SMTP_HOST": "",
            "DATABASE_URL": "",
        }
    )
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if IS_WINDOWS else 0
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
    if not port_conflict:
        info(f"Arrancando frontend proxy ({frontend_variant}) en puerto {port} ...")
        frontend_env = os.environ.copy()
        frontend_env.update({"PORT": port, "GAIA_PORT": gaia_port, "FRONTEND_DIR": str(frontend_dir)})
        with open(FRONTEND_LOG, "ab") as log_fh:
            frontend_proc = subprocess.Popen(
                [str(venv_python()), str(SCRIPT_DIR / "scripts" / "local_proxy.py")],
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
    _local_show_info(port, gaia_port, admin_email)
    if port_conflict:
        warn(f"ATENCIÓN: el frontend usa el puerto {port} ocupado por otro proceso.")
        warn(f"Accede directamente al backend › http://localhost:{gaia_port}")
    info("Logs → python3 gaia.py logs --local   |   Para detener → python3 gaia.py stop --local")


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


def cmd_local_restart(frontend_arg: str | None) -> None:
    cmd_local_stop()
    cmd_local_start(frontend_arg)


def cmd_local_status() -> None:
    print()
    for svc, pidfile in (("backend", BACKEND_PID_FILE), ("frontend", FRONTEND_PID_FILE)):
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


def cmd_local_logs() -> None:
    LOCAL_DIR.mkdir(parents=True, exist_ok=True)
    BACKEND_LOG.touch(exist_ok=True)
    FRONTEND_LOG.touch(exist_ok=True)
    info("Mostrando logs (Ctrl+C para salir)...")

    handles = {}
    for label, path in (("backend", BACKEND_LOG), ("frontend", FRONTEND_LOG)):
        fh = open(path, "r", encoding="utf-8", errors="replace")
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
    finally:
        for fh in handles.values():
            fh.close()


# ── Comandos Docker ───────────────────────────────────────────────────────────


def _copy_git_tree(src: Path, dest: Path) -> None:
    # Copia SOLO los ficheros trackeados en git de src a dest — nunca lo que
    # esté en el disco pero no comiteado (data/, .env, __pycache__,
    # node_modules, .DS_Store, .claude/settings.local.json, caches, bases de
    # datos locales, credenciales...), aunque exista físicamente en esta
    # máquina. Así una imagen que se publica en un registro público (Docker
    # Hub) nunca puede llevarse algo sensible o basura local por accidente —
    # es exactamente lo mismo que vería un `git clone` limpio (como el que
    # hace la CI). Réplica de `git ls-files`, no de `shutil.copytree`.
    result = subprocess.run(
        ["git", "-C", str(src), "ls-files", "-z"],
        capture_output=True, check=True,
    )
    files = [f for f in result.stdout.decode("utf-8").split("\0") if f]
    if not files:
        error(f"'{src}' no parece un repositorio git con ficheros trackeados.")
    for rel in files:
        s = src / rel
        if not s.is_file():
            continue  # symlink roto, submódulo, etc.
        d = dest / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(s, d)


def _ensure_buildx_builder() -> None:
    if not run_ok(["docker", "buildx", "inspect", "multiarch"]):
        info("Creando builder multi-plataforma...")
        subprocess.run(["docker", "buildx", "create", "--name", "multiarch", "--driver", "docker-container", "--use"], check=True)
        subprocess.run(["docker", "buildx", "inspect", "--bootstrap"], check=True)
    else:
        subprocess.run(["docker", "buildx", "use", "multiarch"], check=True)


def _push_variant(frontend_variant: str, hub_user: str, tag: str) -> str:
    unified_img = f"{hub_user}/app:{tag}"
    backend_src = Path(os.environ.get("DEV_BACKEND_REPO") or (REPOS_ROOT / "backend_fastapi")).resolve()

    if frontend_variant == "vanilla":
        frontend_dirname = "frontend_vanilla"
        dockerfile_name = "Dockerfile.unified.vanilla"
        entrypoint_name = "entrypoint-unified-vanilla.sh"
    else:
        frontend_dirname = "frontend_react"
        dockerfile_name = "Dockerfile.unified"
        entrypoint_name = "entrypoint-unified.sh"
    frontend_src = Path(os.environ.get("DEV_FRONTEND_REPO") or (REPOS_ROOT / frontend_dirname)).resolve()

    info(f"Construyendo imagen unificada · frontend={frontend_variant} · tag={tag}")

    tmpdir = Path(tempfile.mkdtemp(prefix="iagentshub_push_"))
    try:
        info("Preparando contexto de build (solo ficheros trackeados en git)...")
        _copy_git_tree(backend_src, tmpdir / "backend")
        _copy_git_tree(frontend_src, tmpdir / "frontend")
        shutil.copy2(IAGENTS_DIR / "docker" / dockerfile_name, tmpdir / "Dockerfile")
        shutil.copy2(IAGENTS_DIR / "docker" / "supervisord.conf", tmpdir / "supervisord.conf")
        shutil.copy2(IAGENTS_DIR / "docker" / entrypoint_name, tmpdir / "entrypoint-unified.sh")

        info(f"Construyendo imagen multi-plataforma (linux/amd64, linux/arm64) → {unified_img}")
        info("Esto tarda unos minutos la primera vez...")
        subprocess.run(
            [
                "docker", "buildx", "build",
                "--platform", "linux/amd64,linux/arm64",
                "--push",
                "-t", unified_img,
                str(tmpdir),
            ],
            check=True,
        )
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    return unified_img


def cmd_push(frontend_arg: str | None) -> None:
    check_docker()
    ensure_env()

    if frontend_arg is not None and frontend_arg not in ("vanilla", "react"):
        error(f"--frontend debe ser 'vanilla' o 'react' (valor: {frontend_arg})")

    hub_user = read_env_var(ENV_FILE, "DOCKER_HUB_USER", "iagenthub")
    _ensure_buildx_builder()

    if frontend_arg is None:
        # Sin --frontend: se suben TODAS las variantes (:latest y :vanilla).
        # Se ignora IMAGE_TAG de .env aquí — es el tag a *descargar* en modo
        # --hub, no tiene sentido como tag común para ambas variantes al subir.
        info("Sin --frontend: se construyen y suben todas las variantes (react + vanilla).")
        pushed = [
            _push_variant("react", hub_user, "latest"),
            _push_variant("vanilla", hub_user, "vanilla"),
        ]
    else:
        tag_default = "vanilla" if frontend_arg == "vanilla" else "latest"
        tag = read_env_var(ENV_FILE, "IMAGE_TAG", "") or tag_default
        pushed = [_push_variant(frontend_arg, hub_user, tag)]

    print()
    success("Imágenes publicadas en Docker Hub:")
    for img in pushed:
        success(f"  • {img}")
    info("Para desplegar: python3 gaia.py start --hub  (en cualquier servidor con Docker)")
    info("Instalación directa: curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash")


def cmd_start(compose: list[str], dev: bool, hub: bool) -> None:
    check_docker()
    ensure_env()
    env = os.environ.copy()
    inject_github_token(env)
    if dev:
        info("Modo desarrollo — usando repos locales")
    if hub:
        info("Modo Hub — usando imágenes de Docker Hub")
        info("Descargando imágenes actualizadas...")
        subprocess.run(compose + ["pull"], env=env, check=True)
    info("Construyendo e iniciando servicios...")
    subprocess.run(compose + ["rm", "-f", "data-init"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if hub:
        subprocess.run(compose + ["up", "-d"], env=env, check=True)
    else:
        subprocess.run(compose + ["up", "-d", "--build"], env=env, check=True)
    print()
    success(f"iAgents Hub en marcha → http://localhost:{get_port()}")
    _show_admin_info(compose)


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
        subprocess.run(compose + ["logs", "-f", "--tail=100"])
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
        info("Modo Hub — descargando imágenes actualizadas de Docker Hub")
    info("Actualizando a la última versión...")
    subprocess.run(compose + ["rm", "-f", "data-init"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(compose + ["down"], env=env, check=True)
    if hub:
        subprocess.run(compose + ["pull"], env=env, check=True)
        subprocess.run(compose + ["up", "-d"], env=env, check=True)
    else:
        subprocess.run(compose + ["up", "-d", "--build"], env=env, check=True)
    print()
    success(f"Actualización completada → http://localhost:{get_port()}")
    _show_admin_info(compose)


def cmd_status(compose: list[str]) -> None:
    check_docker()
    subprocess.run(compose + ["ps"])


# ── Ayuda ──────────────────────────────────────────────────────────────────────


def _print_local_usage() -> None:
    print(f"{BOLD}Uso:{RESET} python3 gaia.py <comando> --local")
    print()
    print("  start    Arranca backend (uvicorn) y frontend (proxy Python) sin Docker")
    print("  stop     Detiene los servicios locales")
    print("  restart  Detiene y vuelve a arrancar los servicios locales")
    print("  logs     Muestra los logs en tiempo real")
    print("  status   Estado de los procesos locales")
    print()
    print(f"  {YELLOW}Base de datos: SQLite en ../iagentshub/data/hub.db  (con persistencia){RESET}")
    print(f"  {YELLOW}Sin PostgreSQL ni contenedores Docker.{RESET}")
    print(f"  {YELLOW}El frontend (vanilla/react) se fija con GAIA_FRONTEND_VARIANT en .env.{RESET}")
    print()


def _print_docker_usage() -> None:
    print(f"{BOLD}Uso:{RESET} python3 gaia.py <comando> [--dev] [--hub] [--local]")
    print()
    print("  start    Arranca los servicios")
    print("  stop     Detiene los servicios")
    print("  restart  Detiene y vuelve a arrancar los servicios (sin descargar nada nuevo)")
    print("  logs     Muestra los logs en tiempo real")
    print("  update   Actualiza a la última versión y reinicia")
    print("  status   Estado de los contenedores")
    print("  push     Construye imágenes y las sube a Docker Hub  (requiere --hub o sin flag)")
    print()
    print(f"{BOLD}Flags:{RESET}")
    print("  --dev              Usa repos locales (../backend_fastapi, ../frontend_vanilla) con hot reload")
    print("  --hub              Usa imágenes pre-construidas de Docker Hub (despliegue rápido)")
    print("  --local            Sin Docker: uvicorn + proxy Python (SQLite, sin PostgreSQL)")
    print("  --frontend=<var>   Limita 'push' a una variante: vanilla|react (default: sube ambas)")
    print()
    print(f"{BOLD}Flujo recomendado para despliegues rápidos (--hub):{RESET}")
    print("  1. En tu máquina:   python3 gaia.py push              # construye y sube imágenes")
    print("  2. En el servidor:  python3 gaia.py start --hub       # descarga y arranca")
    print("  3. Para actualizar: python3 gaia.py update --hub      # pull + reinicio")
    print()


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    dev = local = hub = help_mode = False
    frontend_arg: str | None = None
    positional: list[str] = []

    for arg in sys.argv[1:]:
        if arg == "--dev":
            dev = True
        elif arg == "--local":
            local = True
        elif arg == "--hub":
            hub = True
        elif arg.startswith("--frontend="):
            frontend_arg = arg.split("=", 1)[1]
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

    if local:
        if help_mode or not command:
            _print_local_usage()
            sys.exit(0 if help_mode else 1)
        if command == "start":
            cmd_local_start(frontend_arg)
        elif command == "stop":
            cmd_local_stop()
        elif command == "restart":
            cmd_local_restart(frontend_arg)
        elif command == "logs":
            cmd_local_logs()
        elif command == "status":
            cmd_local_status()
        else:
            error(f"Comando desconocido: {command}. Usa: python3 gaia.py --help --local")
        return

    if dev:
        compose = ["docker", "compose", "-f", "docker-compose.yml", "-f", "docker-compose.dev.yml"]
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
        cmd_push(frontend_arg)
    else:
        error(f"Comando desconocido: {command}. Usa: python3 gaia.py --help")


if __name__ == "__main__":
    main()
