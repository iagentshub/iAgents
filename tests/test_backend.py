"""Ejecuta la suite de tests del backend y verifica que pasen.

El directorio del backend se resuelve en este orden:
  1. Variable de entorno BACKEND_DIR
  2. ../backend  (repo hermano en el mismo workspace)
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
_DEFAULT_BACKEND = REPO_ROOT.parent / "backend"


def _backend_dir() -> Path:
    env = os.environ.get("BACKEND_DIR")
    return Path(env) if env else _DEFAULT_BACKEND


def test_backend_dir_exists():
    d = _backend_dir()
    assert d.is_dir(), (
        f"Directorio del backend no encontrado: {d}. "
        "Define la variable de entorno BACKEND_DIR si esta en una ruta distinta."
    )


def test_backend_has_rtests():
    d = _backend_dir()
    assert (d / "rtests.py").exists(), f"rtests.py no encontrado en {d}"


def test_backend_tests_pass():
    """Ejecuta python3 rtests.py en el directorio del backend."""
    d = _backend_dir()
    result = subprocess.run(
        [sys.executable, "rtests.py"],
        cwd=str(d),
    )
    assert result.returncode == 0, (
        f"Los tests del backend fallaron (codigo de salida {result.returncode})."
        "Consulta la salida anterior para mas detalles."
    )
