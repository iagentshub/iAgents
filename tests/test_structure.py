"""Tests de estructura: docker-compose, ficheros de configuracion y datos."""

from __future__ import annotations

import json
import warnings
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).parent.parent


# helpers


def _load_compose() -> dict:
    return yaml.safe_load(
        (REPO_ROOT / "docker-compose.yml").read_text(encoding="utf-8")
    )


# .env / configuracion


def test_env_example_exists():
    assert (REPO_ROOT / ".env.example").exists(), ".env.example no encontrado"


def test_env_warning_if_missing():
    if not (REPO_ROOT / ".env").exists():
        warnings.warn(
            ".env no existe. Copia .env.example y ajusta los valores antes de desplegar.",
            UserWarning,
            stacklevel=1,
        )


def test_docker_compose_exists():
    assert (REPO_ROOT / "docker-compose.yml").exists()


# docker-compose: servicios


def test_required_services_present():
    compose = _load_compose()
    services = list(compose.get("services", {}).keys())
    for required in ("data-init", "backend", "frontend"):
        assert required in services, (
            f"Servicio {required!r} no encontrado en docker-compose.yml"
        )


def test_backend_has_healthcheck():
    compose = _load_compose()
    backend = compose["services"]["backend"]
    assert "healthcheck" in backend, "El servicio backend no tiene healthcheck definido"


def test_frontend_exposes_port():
    compose = _load_compose()
    frontend = compose["services"]["frontend"]
    assert "ports" in frontend, "El servicio frontend no expone ningun puerto"


def test_backend_depends_on_data_init():
    compose = _load_compose()
    backend = compose["services"]["backend"]
    depends = backend.get("depends_on", {})
    deps = list(depends.keys()) if isinstance(depends, dict) else depends
    assert "data-init" in deps, "backend no depende de data-init"


def test_backend_mounts_data_volume():
    compose = _load_compose()
    backend = compose["services"]["backend"]
    volumes = backend.get("volumes", [])
    assert any("data" in v for v in volumes), "Backend no monta el volumen de datos"


# estructura de datos


def test_data_dir_exists():
    assert (REPO_ROOT / "data").is_dir()


def test_data_subdirs_exist():
    # Tras la migración a SQLite, todos los datos (accounts, agents, connections,
    # memory, skills) están en hub.db. Solo logs/ sigue siendo filesystem.
    for subdir in ("logs",):
        p = REPO_ROOT / "data" / subdir
        assert p.is_dir(), f"data/{subdir}/ no existe"


def test_settings_json_exists():
    # settings.json es runtime (en .gitignore); lo crea `gaia.py` o `data-init`.
    # En un clone limpio no existe → skip, no error de estructura.
    settings = REPO_ROOT / "data" / "settings.json"
    if not settings.exists():
        pytest.skip("data/settings.json no existe todavía (ejecuta: python3 gaia.py start)")


def test_settings_json_has_required_keys():
    settings_path = REPO_ROOT / "data" / "settings.json"
    if not settings_path.exists():
        pytest.skip("data/settings.json no existe todavía (ejecuta: python3 gaia.py start)")
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
    for key in ("jwt_secret",):
        assert key in settings, f"settings.json no tiene la clave {key!r}"


# skills source


def test_docker_compose_references_skills_repo():
    # Skills are cloned at runtime by the data-init service, not via git submodules
    compose_text = (REPO_ROOT / "docker-compose.yml").read_text(encoding="utf-8")
    assert "skills" in compose_text.lower(), (
        "docker-compose.yml no referencia el repositorio de skills"
    )
    assert "SKILLS_REPO" in compose_text, "docker-compose.yml no define SKILLS_REPO"
