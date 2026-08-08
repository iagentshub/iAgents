"""Salida de consola y confirmaciones de operaciones destructivas."""

from __future__ import annotations

import platform
import sys

IS_WINDOWS = platform.system() == "Windows"

# Con stdout redirigido (pipe, fichero, CI) Windows usa cp1252 y los caracteres
# de caja de los banners revientan con UnicodeEncodeError.
if IS_WINDOWS:
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

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


def error(msg: str) -> None:
    print(f"{RED}{BOLD}[gaia]{RESET} {msg}", file=sys.stderr)
    sys.exit(1)


def _confirm_destructive(scope_desc: str, yes: bool) -> None:
    """Exige confirmación explícita antes de un borrado irreversible.

    El compose por defecto (sin --dev/--hub/--local) es el que usa el
    despliegue en producción — un 'reset' accidental ahí destruye datos
    reales, así que no basta con un simple aviso.
    """
    print()
    warn("╔══════════════════════════════════════════════════════════════╗")
    warn("║  ATENCIÓN: esta acción es DESTRUCTIVA e IRREVERSIBLE           ║")
    warn("╚══════════════════════════════════════════════════════════════╝")
    warn(f"Se eliminará POR COMPLETO {scope_desc}:")
    warn("  • Todos los usuarios y contraseñas")
    warn(
        "  • Todos los agentes, skills, conexiones (con API keys cifradas) y workflows"
    )
    warn("  • Todo el historial de chats, memoria y contadores de tokens")
    warn("  • La configuración (settings.json, secret JWT)")
    print()
    if yes:
        warn("--yes indicado: continuando sin confirmación interactiva.")
        return
    if not sys.stdin.isatty():
        error(
            "Entrada no interactiva: repite el comando con --yes para confirmar el borrado."
        )
    resp = input(f"{BOLD}Escribe RESET para confirmar: {RESET}").strip()
    if resp != "RESET":
        error("Confirmación no recibida. Abortando sin cambios.")
