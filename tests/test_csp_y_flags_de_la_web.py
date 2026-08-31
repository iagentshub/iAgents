"""Guard del acoplamiento entre los flags de la web y la CSP que nginx sirve.

`app_flutter/tool/build_web.sh` compila la app con `--no-web-resources-cdn`,
que sirve CanvasKit desde el propio origen en vez de pedirlo a
`www.gstatic.com`. La otra mitad de esa decisión vive en otro repositorio: el
bloque `location ^~ /app/` de `frontend_react/nginx.react.conf`, cuya CSP —por
eso mismo— **no** permite `www.gstatic.com` en `script-src`.

Quitar el flag sin tocar la CSP deja la aplicación autenticada **en blanco**:
Flutter pide CanvasKit al CDN, el navegador lo bloquea por política y no hay
error de servidor, ni log, ni test de comportamiento que cambie.

Hasta ahora eso lo sostenía un comentario. Las guardas que existían vigilan que
la web se compile *con el script* (`web_bundle_budget_test.dart` en app_flutter
y `test_gaia_build_push_compila_la_web_con_el_script` aquí), que es una
pregunta distinta: cubren quién compila, no si las dos mitades siguen de
acuerdo.

Los repositorios hermanos se resuelven como en test_backend.py: variable de
entorno, o directorio hermano. Si no están, se salta.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent

# El recurso que decide el acoplamiento: con el flag se sirve desde nuestro
# origen; sin él, Flutter lo pide a este host y la CSP tiene que permitirlo.
CDN_DE_CANVASKIT = "www.gstatic.com"
FLAG = "--no-web-resources-cdn"


def _repo_dir(nombre: str, variable: str) -> Path:
    env = os.environ.get(variable)
    return Path(env) if env else REPO_ROOT.parent / nombre


def _csp_de_la_zona_autenticada(conf: str) -> str:
    """La Content-Security-Policy del bloque `location ^~ /app/`.

    Es la única que importa aquí: la de la raíz gobierna las páginas públicas,
    que no cargan CanvasKit.
    """
    inicio = conf.find("location ^~ /app/")
    assert inicio != -1, "nginx.react.conf ya no tiene el bloque `location ^~ /app/`"

    resto = conf[inicio:]
    fin = resto.find("\n    location ")
    bloque = resto[: fin if fin != -1 else len(resto)]

    politica = re.search(r'add_header Content-Security-Policy\s+"([^"]+)"', bloque)
    assert politica, "el bloque `location ^~ /app/` se quedo sin CSP"
    return politica.group(1)


def test_la_csp_de_app_y_los_flags_de_la_web_siguen_de_acuerdo():
    flutter = _repo_dir("app_flutter", "APP_FLUTTER_DIR")
    react = _repo_dir("frontend_react", "FRONTEND_REACT_DIR")
    if not flutter.is_dir() or not react.is_dir():
        pytest.skip("app_flutter o frontend_react no estan clonados al lado")

    guion = flutter / "tool" / "build_web.sh"
    conf = react / "nginx.react.conf"
    if not guion.is_file() or not conf.is_file():
        pytest.skip("build_web.sh o nginx.react.conf ya no estan donde se espera")

    sirve_canvaskit_del_origen = FLAG in guion.read_text(encoding="utf-8")
    csp = _csp_de_la_zona_autenticada(conf.read_text(encoding="utf-8"))
    script_src = re.search(r"script-src([^;]*)", csp)
    assert script_src, "la CSP de /app/ se quedo sin script-src"
    csp_permite_el_cdn = CDN_DE_CANVASKIT in script_src.group(1)

    if sirve_canvaskit_del_origen:
        assert not csp_permite_el_cdn, (
            f"build_web.sh usa {FLAG}, asi que CanvasKit sale de nuestro origen "
            f"y {CDN_DE_CANVASKIT} sobra en el script-src de la zona "
            "autenticada: un permiso que nadie usa es superficie de mas"
        )
    else:
        assert csp_permite_el_cdn, (
            f"build_web.sh ya no usa {FLAG}, asi que Flutter pedira CanvasKit a "
            f"{CDN_DE_CANVASKIT} y la CSP de `location ^~ /app/` lo bloquea. La "
            "aplicacion autenticada sale EN BLANCO, sin error ni log: hay que "
            "permitirlo en script-src o devolver el flag"
        )
