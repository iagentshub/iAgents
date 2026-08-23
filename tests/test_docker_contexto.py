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
  3. Un workflow que instale Flutter con `channel: stable` a secas — compilaba
     la app con la versión que hubiera ese día, mientras el CI de app_flutter
     validaba otra fijada a mano. La imagen que se despliega salía de una
     versión que nadie había probado.

Los repositorios hermanos se resuelven como en test_backend.py: variable de
entorno, o directorio hermano. Si no están, se salta.
"""

from __future__ import annotations

import os
import re
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


@pytest.mark.parametrize("repo", ["iAgents", *REPOS_HERMANOS])
def test_flutter_se_instala_con_la_version_del_pubspec(repo):
    """La versión de Flutter vive en app_flutter/pubspec.yaml y solo ahí.

    Los tres repos compilan la misma app: este y backend_fastapi hacen checkout
    de app_flutter para construir la imagen unificada, y app_flutter lo hace en
    su propio CI. Cuando cada uno decidía su versión por su cuenta, la que
    llegaba a producción y la que se validaba eran distintas sin que nada
    fallara.
    """
    raiz = REPO_ROOT if repo == "iAgents" else _repo_dir(repo)
    if not raiz.is_dir():
        pytest.skip(f"{repo} no esta clonado junto a este repositorio")

    wf_dir = raiz / ".github" / "workflows"
    if not wf_dir.is_dir():
        pytest.skip(f"{repo} no tiene workflows")

    con_flutter = [
        f for f in sorted(wf_dir.glob("*.yml")) if "subosito/flutter-action" in f.read_text()
    ]
    if not con_flutter:
        pytest.skip(f"{repo} no instala Flutter en ningun workflow")

    for wf in con_flutter:
        contenido = wf.read_text()
        assert "flutter-version-file" in contenido, (
            f"{repo}/.github/workflows/{wf.name} instala Flutter sin "
            "flutter-version-file: toma la version de 'channel: stable', que "
            "cambia sola, o una escrita a mano que se separa del pubspec."
        )
        assert not re.search(r"^\s*flutter-version:\s*\d", contenido, re.M), (
            f"{repo}/.github/workflows/{wf.name} fija la version de Flutter a "
            "mano. La fuente es 'environment: flutter:' de app_flutter/"
            "pubspec.yaml; escrita aqui, las dos se separan en silencio."
        )


def test_el_pubspec_de_app_flutter_fija_una_version_exacta():
    """Sin version exacta en el pubspec, `flutter-version-file` no resuelve."""
    app_flutter = _repo_dir("app_flutter")
    pubspec = app_flutter / "pubspec.yaml"
    if not pubspec.is_file():
        pytest.skip("app_flutter no esta clonado junto a este repositorio")

    assert re.search(r"^\s*flutter:\s*\d+\.\d+\.\d+\s*$", pubspec.read_text(), re.M), (
        "app_flutter/pubspec.yaml tiene que declarar 'flutter: X.Y.Z' exacto "
        "dentro de 'environment'. Es lo que leen los tres workflows, y la "
        "action exige una version exacta, no un rango."
    )
