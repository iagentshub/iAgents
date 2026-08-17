"""Guards del contexto de build de la imagen unificada.

Tres repositorios publican `ghcr.io/iagentshub/app` desde el mismo
`docker/Dockerfile.unified`, cada uno con su propio paso «Preparar contexto de
build». Los dos fallos que cubren estos tests no rompen el build ni se ven en
la imagen resultante:

  1. Instalar desde `requirements.txt` en vez de `requirements.lock` — la
     imagen que se despliega quedaba con rangos flotantes mientras la
     standalone usaba el lock con hashes.
  2. Un workflow que no copie `dockerignore.unified` — Docker solo lee el
     `.dockerignore` de la RAÍZ del contexto, así que el de backend_fastapi no
     aplica aquí y el `COPY backend/` se lleva tests/, docs/ y el .git dentro.

Los repositorios hermanos se resuelven como en test_backend.py: variable de
entorno, o directorio hermano. Si no están, se salta.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent
DOCKER_DIR = REPO_ROOT / "docker"

# Cada repo que prepara un build-ctx, con la variable que reubica su clon.
REPOS_HERMANOS = {
    "backend_fastapi": "BACKEND_DIR",
    "app_flutter": "APP_FLUTTER_DIR",
}


def _repo_dir(nombre: str) -> Path:
    env = os.environ.get(REPOS_HERMANOS[nombre])
    return Path(env) if env else REPO_ROOT.parent / nombre


def _workflows_con_build_ctx(raiz: Path) -> list[Path]:
    wf = raiz / ".github" / "workflows"
    if not wf.is_dir():
        return []
    return [f for f in sorted(wf.glob("*.yml")) if "build-ctx" in f.read_text()]


def test_dockerignore_unified_exists():
    assert (DOCKER_DIR / "dockerignore.unified").is_file(), (
        "docker/dockerignore.unified no existe. Sin el, el contexto unificado "
        "no tiene .dockerignore y el COPY backend/ se lleva el arbol entero."
    )


def test_dockerignore_unified_whitelists_backend():
    """La lista blanca del backend es lo que mantiene tests/ y .git fuera."""
    contenido = (DOCKER_DIR / "dockerignore.unified").read_text()
    assert "backend/*" in contenido, (
        "Falta el patron 'backend/*': sin el, las lineas '!backend/...' no "
        "reincluyen nada y el directorio entra completo."
    )
    for necesario in ("!backend/app", "!backend/main.py", "!backend/requirements.lock"):
        assert necesario in contenido, (
            f"Falta '{necesario}' en dockerignore.unified. Es lo minimo que el "
            "contenedor necesita: supervisord arranca 'python /app/main.py'."
        )


def test_dockerfile_unified_instala_desde_el_lock():
    # Solo las instrucciones: los comentarios de cabecera nombran
    # requirements.txt justamente para explicar por que ya no se usa.
    instrucciones = [
        ln
        for ln in (DOCKER_DIR / "Dockerfile.unified").read_text().splitlines()
        if ln.strip() and not ln.lstrip().startswith("#")
    ]
    contenido = "\n".join(instrucciones)

    assert "--require-hashes" in contenido, (
        "Dockerfile.unified instala sin --require-hashes. La imagen que se "
        "despliega quedaria con garantias mas debiles que la standalone."
    )
    assert "requirements.lock" in contenido
    assert "requirements.txt" not in contenido, (
        "Dockerfile.unified vuelve a instalar desde requirements.txt: son "
        "rangos flotantes resueltos el dia del build. El lock es la fuente."
    )


def test_gaia_build_push_copia_el_dockerignore():
    """`gaia build-push` construye la misma imagen desde la línea de órdenes.

    Copia solo lo trackeado en git, lo que deja fuera el .git y los ficheros
    sueltos — pero tests/ y docs/ sí están trackeados.
    """
    build_push = REPO_ROOT / "gaia_cli" / "build_push.py"
    if not build_push.is_file():
        pytest.skip("gaia_cli/build_push.py ya no existe")

    contenido = build_push.read_text()
    if "Dockerfile.unified" not in contenido:
        pytest.skip("build_push.py ya no construye la imagen unificada")

    assert "dockerignore.unified" in contenido, (
        "build_push.py prepara un contexto para Dockerfile.unified pero no "
        "copia docker/dockerignore.unified como .dockerignore del contexto."
    )


@pytest.mark.parametrize("repo", ["iAgents", *REPOS_HERMANOS])
def test_los_workflows_copian_el_dockerignore(repo):
    """Todo workflow que prepare un build-ctx tiene que copiar el ignore."""
    raiz = REPO_ROOT if repo == "iAgents" else _repo_dir(repo)
    if not raiz.is_dir():
        pytest.skip(f"{repo} no esta clonado junto a este repositorio")

    workflows = _workflows_con_build_ctx(raiz)
    if not workflows:
        pytest.skip(f"{repo} ya no prepara ningun build-ctx")

    for wf in workflows:
        assert "dockerignore.unified" in wf.read_text(), (
            f"{repo}/.github/workflows/{wf.name} prepara un build-ctx pero no "
            "copia docker/dockerignore.unified como build-ctx/.dockerignore. "
            "La imagen se publicaria con tests/, docs/ y el .git dentro, y "
            "nada mas lo notaria."
        )
