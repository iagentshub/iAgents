"""Preparación, construcción multi-plataforma y publicación de imágenes."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from .common import (
    ENV_FILE,
    IAGENTS_DIR,
    REPOS_ROOT,
    check_docker,
    ensure_env,
    read_env_var,
    run_ok,
)
from .console import error, info, success


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
        capture_output=True,
        check=True,
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
        subprocess.run(
            [
                "docker",
                "buildx",
                "create",
                "--name",
                "multiarch",
                "--driver",
                "docker-container",
                "--use",
            ],
            check=True,
        )
        subprocess.run(["docker", "buildx", "inspect", "--bootstrap"], check=True)
    else:
        subprocess.run(["docker", "buildx", "use", "multiarch"], check=True)


def _git_short_sha(repo: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() or "dev"


def _push_react(image_repository: str, tag: str) -> str:
    unified_img = f"{image_repository}:{tag}"
    backend_src = Path(
        os.environ.get("DEV_BACKEND_REPO") or (REPOS_ROOT / "backend_fastapi")
    ).resolve()
    frontend_src = Path(
        os.environ.get("DEV_FRONTEND_REPO") or (REPOS_ROOT / "frontend_react")
    ).resolve()
    flutter_src = Path(
        os.environ.get("DEV_FLUTTER_REPO") or (REPOS_ROOT / "app_flutter")
    ).resolve()

    # Versión YYYYMMDDHHMMSS (UTC) — misma convención que los workflows de CI.
    # Se hornea en la imagen (GAIA_VERSION) y se publica como tag inmutable
    # adicional con el prefijo react- para que /api/admin/check-update pueda
    # comparar únicamente versiones de la aplicación web soportada.
    version = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    version_img = f"{image_repository}:react-{version}"
    backend_commit = _git_short_sha(backend_src)
    frontend_commit = _git_short_sha(frontend_src)

    info(f"Construyendo imagen unificada React · tag={tag} · versión={version}")

    tmpdir = Path(tempfile.mkdtemp(prefix="iagentshub_push_"))
    try:
        info("Preparando contexto de build (solo ficheros trackeados en git)...")
        _copy_git_tree(backend_src, tmpdir / "backend")
        _copy_git_tree(frontend_src, tmpdir / "frontend")
        if not (flutter_src / "pubspec.yaml").is_file():
            error("No se encontró pubspec.yaml en ../app_flutter/")
        # `flutter build web` no borra lo que dejó de generar: los ficheros de
        # una compilación anterior siguen ahí y entran enteros en el copytree de
        # más abajo. El contexto de backend y frontend está a salvo porque
        # `_copy_git_tree` solo copia lo trackeado en git; este viene de un
        # directorio generado, así que la lista blanca no aplica y un asset
        # rancio acabaría horneado en la imagen pública sirviendo /app/.
        # Se borra solo build/web, no `flutter clean` entero: basta para
        # garantizar que lo que se copia es de esta compilación, y conserva el
        # resto de la caché (un clean completo añade minutos a cada push).
        web_out = flutter_src / "build" / "web"
        if web_out.exists():
            info("Descartando build/web anterior...")
            shutil.rmtree(web_out)
        info("Compilando Flutter Web para /app/...")
        # Se llama al script del repo, NO a `flutter build web` a secas. Sus
        # flags tienen la otra mitad en la CSP que sirve nginx: sin
        # `--no-web-resources-cdn`, Flutter pide CanvasKit a www.gstatic.com y
        # la política del bloque `location ^~ /app/` no lo permite. El
        # resultado es la aplicación autenticada en blanco, sin error visible
        # ni test que se entere. Este camino se saltaba el script y publicaba
        # justo esa imagen; los tres workflows sí lo usaban.
        build_web = flutter_src / "tool" / "build_web.sh"
        if not build_web.is_file():
            error(f"No se encontró {build_web}: no se puede compilar la web.")
        # Se invoca con `bash` en vez de confiar en el bit de ejecución: un
        # checkout en Windows no lo conserva.
        subprocess.run(
            ["bash", str(build_web), "--base-href", "/app/"],
            cwd=flutter_src,
            check=True,
        )
        shutil.copytree(flutter_src / "build" / "web", tmpdir / "flutter-web")
        shutil.copy2(
            IAGENTS_DIR / "docker" / "Dockerfile.unified", tmpdir / "Dockerfile"
        )
        shutil.copy2(
            IAGENTS_DIR / "docker" / "supervisord.conf", tmpdir / "supervisord.conf"
        )
        shutil.copy2(
            IAGENTS_DIR / "docker" / "entrypoint-unified.sh",
            tmpdir / "entrypoint-unified.sh",
        )
        # `_copy_git_tree` deja fuera lo no trackeado, pero tests/ y docs/ sí lo
        # están. El ignore conserva tests/ para Centinel, excluye docs/ y es el
        # único que Docker lee porque la raíz del contexto es este tmpdir.
        shutil.copy2(
            IAGENTS_DIR / "docker" / "dockerignore.unified", tmpdir / ".dockerignore"
        )

        info(
            f"Construyendo imagen multi-plataforma (linux/amd64, linux/arm64) → {unified_img}"
        )
        info("Esto tarda unos minutos la primera vez...")
        subprocess.run(
            [
                "docker",
                "buildx",
                "build",
                "--platform",
                "linux/amd64,linux/arm64",
                "--build-arg",
                f"GAIA_VERSION={version}",
                "--build-arg",
                f"BACKEND_COMMIT={backend_commit}",
                "--build-arg",
                f"FRONTEND_COMMIT={frontend_commit}",
                "--push",
                "-t",
                unified_img,
                "-t",
                version_img,
                str(tmpdir),
            ],
            check=True,
        )
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    return unified_img


def cmd_push() -> None:
    check_docker()
    ensure_env()

    image_repository = read_env_var(
        ENV_FILE, "IMAGE_REPOSITORY", "ghcr.io/iagentshub/app"
    )
    _ensure_buildx_builder()

    tag = read_env_var(ENV_FILE, "IMAGE_TAG", "") or "latest"
    pushed = [_push_react(image_repository, tag)]

    print()
    success("Imágenes publicadas en GitHub Container Registry:")
    for img in pushed:
        success(f"  • {img}")
    info(
        "Para desplegar: python3 gaia.py start --hub  (en cualquier servidor con Docker)"
    )
    info(
        "Instalación directa: curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash"
    )
