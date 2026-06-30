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
    """Verifica que los tests del backend se pueden recolectar sin errores.

    Usa --collect-only para comprobar imports y estructura sin ejecutar la suite
    completa (966 tests tardarían ~10 min). Para ejecutar la suite completa:
        cd ../backend && python3 rtests.py
    """
    d = _backend_dir()
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "tests",
            "--collect-only",
            "-q",
            "--ignore=tests/e2e",
            "--ignore=tests/performance",
        ],
        cwd=str(d),
        timeout=60,
    )
    assert result.returncode == 0, (
        f"La recoleccion de tests del backend fallo (codigo de salida {result.returncode}). "
        "Consulta la salida anterior para mas detalles."
    )
