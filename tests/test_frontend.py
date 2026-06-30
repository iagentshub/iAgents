"""Tests del frontend: tests JS en Node.js + análisis estático + lint.

Qué detectan estos tests:
- Bugs de hoisting JS (variable usada antes de declararse)
- URLs de API incorrectas (scope wrong, typos en paths)
- Scripts referenciados en HTML que no existen en disco
- Rutas críticas del frontend que no tienen endpoint en el backend
- Errores de sintaxis JS (node --check)
- Violaciones de estilo/calidad Python (ruff)
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
FRONTEND_DIR = REPO_ROOT.parent / "frontend"
BACKEND_DIR = REPO_ROOT.parent / "backend"


# ── helpers ───────────────────────────────────────────────────────────────────


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _run_node(js_file: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["node", str(js_file)],
        capture_output=True,
        text=True,
    )


def _backend_routes() -> set[str]:
    """Devuelve el conjunto de todas las rutas definidas en el backend.

    Combina el prefix del APIRouter con la ruta del decorator:
      router = APIRouter(prefix="/api/agents")  +  @router.get("")  →  /api/agents
      router = APIRouter()                       +  @router.get("/api/foo")  →  /api/foo
    """
    routes: set[str] = set()
    for f in (BACKEND_DIR / "app" / "api" / "routes").glob("*.py"):
        src = _read(f)
        # Extraer prefix del router (puede haber varios routers por fichero)
        prefixes: list[str] = re.findall(
            r'APIRouter\([^)]*prefix\s*=\s*["\']([^"\']+)["\']',
            src,
        )
        # Un fichero puede tener un router sin prefix
        if not prefixes:
            prefixes = [""]
        # Para simplificar: el primer prefix encontrado aplica a todos los decorators
        # (patrón dominante en este codebase: un router por fichero)
        prefix = prefixes[0] if prefixes else ""
        for m in re.finditer(
            r'@router\.(get|post|put|delete|patch)\s*\(\s*["\']([^"\']*)["\']',
            src,
        ):
            path = m.group(2)
            # Si la ruta ya empieza con /api no añadimos el prefix
            full = (
                path if path.startswith("/api") else (prefix + path).rstrip("/") or "/"
            )
            routes.add(full)
    return routes


# ── Tests Node.js ─────────────────────────────────────────────────────────────


def test_node_disponible():
    """Node.js está instalado y es accesible."""
    r = subprocess.run(["node", "--version"], capture_output=True, text=True)
    assert r.returncode == 0, "Node.js no está disponible en PATH"


def test_js_loads_pasan():
    """test_loads.js: tests de parsers de ficheros locales (Claude, Copilot…)."""
    r = _run_node(FRONTEND_DIR / "tests" / "test_loads.js")
    assert r.returncode == 0, "test_loads.js falló:\n" + r.stdout + r.stderr


def test_js_components_pasan():
    """test_components.js: renderizado de AgentCard y URLs de explore."""
    r = _run_node(FRONTEND_DIR / "tests" / "test_components.js")
    assert r.returncode == 0, "test_components.js falló:\n" + r.stdout + r.stderr


# ── Análisis estático: HTML ───────────────────────────────────────────────────


def test_scripts_html_existen_en_disco():
    """Todo <script src="..."> en páginas HTML apunta a un fichero que existe.

    Sigue el mismo mapeo que nginx.conf:
    - /assets/...  → FRONTEND_DIR/assets/...
    - /pages/...   → FRONTEND_DIR/pages/...
    - /cualquier/  → FRONTEND_DIR/pages/cualquier/  (nginx: try_files /pages$uri)
    - rutas relativas → relativas al directorio del HTML
    """
    missing = []
    for html_file in FRONTEND_DIR.rglob("*.html"):
        text = _read(html_file)
        for src in re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', text):
            if src.startswith(("http", "//")):
                continue
            if src.startswith("/"):
                # nginx sirve /assets/ directamente; el resto via /pages$uri
                if src.startswith("/assets/") or src.startswith("/pages/"):
                    resolved = (FRONTEND_DIR / src.lstrip("/")).resolve()
                else:
                    resolved = (FRONTEND_DIR / "pages" / src.lstrip("/")).resolve()
            else:
                resolved = (html_file.parent / src).resolve()
            if not resolved.exists():
                missing.append(f"{html_file.relative_to(FRONTEND_DIR)}: {src}")
    assert not missing, (
        "Scripts referenciados en HTML que no existen en disco:\n"
        + "\n".join(f"  {m}" for m in sorted(missing))
    )


# ── Análisis estático: regresiones de bugs conocidos ─────────────────────────


def test_agent_card_agentlabels_declarado_antes_de_uso():
    """Regresión: en agent-card.js, 'var agentLabels' aparece antes de agentLabels.indexOf().

    Bug original: agentLabels.indexOf('linked') se llamaba mientras agentLabels
    aún era undefined (var hoisting), causando TypeError y pantalla en blanco.
    """
    src = _read(FRONTEND_DIR / "assets" / "components" / "agent-card" / "agent-card.js")
    render_start = src.find("render: function")
    assert render_start != -1, "función render no encontrada en agent-card.js"
    body = src[render_start:]

    decl_pos = body.find("var agentLabels")
    use_pos = body.find("agentLabels.indexOf")
    assert decl_pos != -1, "'var agentLabels' no encontrada en render()"
    assert use_pos != -1, "'agentLabels.indexOf' no encontrada en render()"
    assert decl_pos < use_pos, (
        "Bug de hoisting detectado: 'agentLabels.indexOf()' aparece en la línea "
        + str(body[:use_pos].count("\n") + 1)
        + " pero 'var agentLabels' se declara en la línea "
        + str(body[:decl_pos].count("\n") + 1)
    )


def test_explore_resource_url_usa_public():
    """Regresión: explore.js construye URLs con scope 'public' para fork/link.

    Bug original: _resourceUrl usaba '/private/' → 404 al intentar fork/link
    porque los recursos del catálogo público no existen en scope private.
    """
    src = _read(FRONTEND_DIR / "pages" / "explore" / "explore.js")
    m = re.search(
        r"function _resourceUrl\(type, id, action\)\s*\{(.+?)\n    \}", src, re.DOTALL
    )
    assert m, "_resourceUrl no encontrada en explore.js"
    body = m.group(1)
    assert "/public/" in body, (
        "_resourceUrl no usa '/public/' para agents/skills.\n"
        "Cuerpo actual:\n" + body.strip()
    )
    assert "/private/" not in body, (
        "Bug de scope: _resourceUrl usa '/private/' en lugar de '/public/'.\n"
        "Cuerpo actual:\n" + body.strip()
    )


# ── Contrato frontend ↔ backend ───────────────────────────────────────────────


def test_rutas_criticas_existen_en_backend():
    """Las rutas clave que usa el frontend existen como endpoints en el backend.

    Detecta URLs de API que el frontend llama pero que el backend no define
    (typos, cambios de nombre, endpoints no implementados).
    """
    routes = _backend_routes()

    # Rutas con path params: convertimos {param} en regex para comparar
    def route_regex(r: str) -> re.Pattern:
        # Las rutas API solo tienen chars seguros (/alnum-_{}); no necesitan re.escape
        pattern = re.sub(r"\{[^}]+\}", "[^/]+", r)
        return re.compile("^" + pattern + "$")

    def exists(pattern: str) -> bool:
        rx = route_regex(pattern)
        return any(rx.match(r) for r in routes)

    checks = [
        ("GET  /api/agents", "/api/agents"),
        ("GET  /api/connections", "/api/connections"),
        ("GET  /api/skills", "/api/skills"),
        ("GET  /api/memory", "/api/memory"),
        ("GET  /api/knowledge", "/api/knowledge"),
        ("GET  /api/explore", "/api/explore"),
        ("GET  /api/social/me/resources", "/api/social/me/resources"),
        ("POST /api/agents/{scope}/{id}/fork", "/api/agents/{scope}/{source_id}/fork"),
        ("POST /api/agents/{scope}/{id}/link", "/api/agents/{scope}/{source_id}/link"),
        ("POST /api/skills/{scope}/{id}/fork", "/api/skills/{scope}/{source_id}/fork"),
        ("POST /api/skills/{scope}/{id}/link", "/api/skills/{scope}/{source_id}/link"),
        ("POST /api/knowledge/{id}/fork", "/api/knowledge/{source_id}/fork"),
        ("POST /api/knowledge/{id}/link", "/api/knowledge/{source_id}/link"),
        (
            "GET  /api/explore/{type}/{id}/preview",
            "/api/explore/{resource_type}/{resource_id}/preview",
        ),
        ("POST /api/agents/public/{id}/try", "/api/agents/{scope}/{source_id}/try"),
    ]

    missing = []
    for desc, pattern in checks:
        if not exists(pattern):
            missing.append(f"  {desc}  →  {pattern}")

    assert not missing, (
        "Rutas que el frontend usa pero que NO existen en el backend:\n"
        + "\n".join(missing)
    )


# ── Lint ──────────────────────────────────────────────────────────────────────


def test_lint_js_sin_errores_de_sintaxis():
    """node --check detecta errores de sintaxis en cualquier fichero JS.

    Cubre: variables sin declarar por typo, llaves sin cerrar, return fuera
    de función, etc. No requiere ESLint instalado.
    """
    js_files = sorted(
        f
        for root in ["pages", "assets/js", "assets/components"]
        for f in (FRONTEND_DIR / root).rglob("*.js")
    )
    assert js_files, "No se encontraron ficheros JS en el frontend"

    errors = []
    for js in js_files:
        r = subprocess.run(
            ["node", "--check", str(js)],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            errors.append(f"{js.relative_to(FRONTEND_DIR)}\n    {r.stderr.strip()}")

    assert not errors, (
        f"{len(errors)} fichero(s) JS con errores de sintaxis:\n"
        + "\n".join(f"  {e}" for e in errors)
    )


def test_lint_python_backend_ruff():
    """ruff comprueba calidad y estilo del código Python del backend.

    Detecta: imports no usados, variables no usadas, código muerto,
    comparaciones erróneas, f-strings mal formadas, etc.
    """
    r = subprocess.run(
        [sys.executable, "-m", "ruff", "check", "app/", "--output-format=concise"],
        capture_output=True,
        text=True,
        cwd=str(BACKEND_DIR),
    )
    assert r.returncode == 0, (
        "ruff encontró violaciones en el backend:\n" + r.stdout + r.stderr
    )


def test_css_html_existen_en_disco():
    """Todo <link rel="stylesheet" href="..."> en páginas HTML apunta a un fichero real.

    Sigue el mismo mapeo nginx que test_scripts_html_existen_en_disco:
    - /assets/  y  /pages/  → directo en FRONTEND_DIR
    - cualquier otra ruta   → FRONTEND_DIR/pages/<ruta>
    """
    missing = []
    for html_file in FRONTEND_DIR.rglob("*.html"):
        text = _read(html_file)
        for href in re.findall(r'<link[^>]+href=["\']([^"\']+)["\']', text):
            if href.startswith(("http", "//")):
                continue
            if not href.endswith(".css"):
                continue
            if href.startswith("/assets/") or href.startswith("/pages/"):
                resolved = (FRONTEND_DIR / href.lstrip("/")).resolve()
            elif href.startswith("/"):
                resolved = (FRONTEND_DIR / "pages" / href.lstrip("/")).resolve()
            else:
                resolved = (html_file.parent / href).resolve()
            if not resolved.exists():
                missing.append(f"{html_file.relative_to(FRONTEND_DIR)}: {href}")
    assert not missing, (
        "CSS referenciados en HTML que no existen en disco:\n"
        + "\n".join(f"  {m}" for m in sorted(missing))
    )


# Scripts que toda página autenticada debe incluir para funcionar correctamente.
# Sólo los realmente universales: pages que no necesitan api.js (explore, labels,
# u) usan fetch() directamente; pages que no necesitan flog.js no llaman log.*
_BASE_SCRIPTS = {
    "/assets/js/i18n.js",  # internacionalización (t() global)
    "/assets/js/config.js",  # configuración global (CFG)
    "/assets/js/theme.js",  # tema visual
    "/assets/js/auth.js",  # autenticación / sesión
}

# Páginas que NO requieren autenticación o son páginas especiales mínimas
_PUBLIC_PAGES = {
    "login",
    "register",
    "forgot-password",
    "reset-password",
    "verify",
    "about",
    "pricing",
    # docs: página especial con sólo flog.js + i18n.js (sin auth ni api)
    "docs",
}


def test_paginas_autenticadas_tienen_scripts_base():
    """Todas las páginas privadas incluyen los scripts base obligatorios.

    Detecta: página nueva creada sin los scripts comunes → TypeError en runtime
    porque `log`, `t()`, `API`, `auth`, etc. no están definidos.
    """
    missing = []
    for html_file in sorted((FRONTEND_DIR / "pages").glob("*/index.html")):
        page_name = html_file.parent.name
        if page_name in _PUBLIC_PAGES:
            continue
        text = _read(html_file)
        scripts_in_page = set(re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', text))
        for required in sorted(_BASE_SCRIPTS):
            if required not in scripts_in_page:
                missing.append(f"pages/{page_name}/index.html: falta {required}")
    assert not missing, "Páginas sin scripts base obligatorios:\n" + "\n".join(
        f"  {m}" for m in missing
    )


def test_backend_no_tiene_rutas_duplicadas():
    """Ningún par (método HTTP, path) está registrado dos veces en el backend.

    En FastAPI, si dos decorators definen la misma ruta+método, la segunda
    queda silenciosamente inaccesible. Este test lo detecta antes de deploy.
    """
    seen: dict[str, str] = {}  # "METHOD /path" → fichero donde se vio primero
    duplicates = []

    for f in sorted((BACKEND_DIR / "app" / "api" / "routes").glob("*.py")):
        src = _read(f)
        prefixes = re.findall(r'APIRouter\([^)]*prefix\s*=\s*["\']([^"\']+)["\']', src)
        prefix = prefixes[0] if prefixes else ""
        for m in re.finditer(
            r'@router\.(get|post|put|delete|patch)\s*\(\s*["\']([^"\']*)["\']',
            src,
        ):
            method = m.group(1).upper()
            path = m.group(2)
            full = (
                path if path.startswith("/api") else (prefix + path).rstrip("/") or "/"
            )
            key = f"{method} {full}"
            if key in seen:
                duplicates.append(
                    f"{key}  (primero en {seen[key]}, repetido en {f.name})"
                )
            else:
                seen[key] = f.name

    assert not duplicates, (
        "Rutas duplicadas en el backend (la segunda nunca se alcanza):\n"
        + "\n".join(f"  {d}" for d in duplicates)
    )


def test_no_innerhtml_con_concatenacion_directa():
    """Detecta asignaciones XSS: innerHTML = variable + string o viceversa.

    Patrón peligroso:   element.innerHTML = userInput + '<br>'
    Patrón seguro:      element.innerHTML = template  (string literal)
                        element.textContent = userInput

    No detecta todos los XSS, pero sí el patrón más común en vanilla JS.
    """
    # Patrón: .innerHTML = ... + ... (asignación con concatenación)
    # Excluimos:
    #   - líneas comentadas
    #   - líneas que usan esc() o _esc() — el dev ya escapó el valor
    #   - líneas donde los únicos valores interpolados son t() / i18n.t() — traducciones
    xss_pattern = re.compile(r"\.innerHTML\s*=[^=][^;]*\+[^;]*;")
    safe_translation = re.compile(
        r'^[\s\'"<>/\w=-]*\+\s*(?:_?esc\(|(?:i18n\.)?t\()[^;]*;'
    )

    violations = []
    roots = [
        (FRONTEND_DIR / "assets").rglob("*.js"),
        (FRONTEND_DIR / "pages").rglob("*.js"),
    ]
    for rglob in roots:
        for js in rglob:
            src = _read(js)
            for i, line in enumerate(src.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                if not xss_pattern.search(line):
                    continue
                # Seguro si usa esc() / _esc() en la línea
                if "esc(" in line:
                    continue
                # Seguro si todos los + son seguidos de t( o i18n.t(
                # (concatenaciones de strings de traducción, no input de usuario)
                parts_after_plus = re.findall(r"\+\s*([^+;]+)", line)
                if all(
                    re.match(r"\s*(?:i18n\.)?t\(", p)
                    or re.match(r"\s*['\"]?", p)
                    and "+" not in p
                    for p in parts_after_plus
                ):
                    continue
                violations.append(
                    f"{js.relative_to(FRONTEND_DIR)}:{i}: {stripped[:120]}"
                )
    assert not violations, (
        "Posibles vectores XSS (innerHTML con concatenación sin esc()):\n"
        + "\n".join(f"  {v}" for v in violations)
    )
