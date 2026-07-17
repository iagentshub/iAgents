#!/usr/bin/env python3
"""Ejecuta los tests de iAgents Hub: estructura del proyecto + tests del backend.

Uso:
    python3 rtests.py                           # todos los tests
    python3 rtests.py -v                        # verbose
    python3 rtests.py tests/test_structure.py  # solo estructura del proyecto
    python3 rtests.py -k "not backend"          # solo tests de estructura (rapido)
    python3 rtests.py -k backend               # solo tests del backend

Variables de entorno:
    BACKEND_DIR   Ruta al repo del backend (default: ../backend_fastapi)
"""
import subprocess
import sys


def main() -> None:
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "-q", "pytest", "pyyaml"],
        check=True,
    )

    args = sys.argv[1:] or ["tests", "-v", "--tb=short"]
    result = subprocess.run(
        [sys.executable, "-m", "pytest", *args],
    )
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
