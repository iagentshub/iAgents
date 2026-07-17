#!/usr/bin/env python3
"""
Servidor de desarrollo sin Docker.

Sirve los ficheros estáticos del frontend e implementa la misma lógica de rutas
que nginx.conf (vanilla) o un fallback SPA (React), además de proxificar /api/
al backend uvicorn. gaia.py fija FRONTEND_DIR según GAIA_FRONTEND_VARIANT.

Variables de entorno:
  PORT          Puerto en el que escucha (default: 8007)
  GAIA_PORT     Puerto del backend (default: 8765)
  FRONTEND_DIR  Directorio con los estáticos a servir (default: ../frontend_vanilla)
"""

from __future__ import annotations

import http.server
import mimetypes
import os
import posixpath
import socketserver
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# ── Configuración ─────────────────────────────────────────────────────────────

_HERE = Path(__file__).parent.resolve()
FRONTEND = Path(os.environ.get("FRONTEND_DIR", str(_HERE / ".." / "frontend_vanilla"))).resolve()
PORT = int(os.environ.get("PORT", "8007"))
BACKEND = f"http://127.0.0.1:{os.environ.get('GAIA_PORT', '8765')}"

# Rutas que redireccionan (sin barra → con barra, o alias)
# Nota: "/" NO está aquí a propósito — se resuelve como fichero normal
# (pages/index.html decide en el cliente entre landing y /login/, según
# landing_enabled). Mismo comportamiento que nginx.conf en producción.
_REDIRECT_302 = {
    "/register": "/register/",
    "/verify": "/verify/",
    "/forgot-password": "/forgot-password/",
    "/reset-password": "/reset-password/",
    "/docs": "/docs/",
    "/about": "/about/",
}
_REDIRECT_301 = {
    "/skills": "/knowledge",
    "/skills/": "/knowledge/",
}


# ── Handler ───────────────────────────────────────────────────────────────────


class DevHandler(http.server.BaseHTTPRequestHandler):
    # ── routing ───────────────────────────────────────────────────────────────

    def do_GET(self) -> None:
        path = urllib.parse.urlsplit(self.path).path

        if path.startswith("/api/"):
            self._proxy()
            return

        if path in _REDIRECT_302:
            self._redirect(_REDIRECT_302[path], 302)
            return
        if path in _REDIRECT_301:
            self._redirect(_REDIRECT_301[path], 301)
            return

        fs = self._resolve(path)
        if fs:
            self._serve_file(fs)
        else:
            self.send_error(404, f"No encontrado: {path}")

    def do_HEAD(self) -> None:
        path = urllib.parse.urlsplit(self.path).path
        if path.startswith("/api/"):
            self._proxy()
            return
        fs = self._resolve(path)
        if fs:
            self._serve_file(fs, head_only=True)
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        self._api_or_405()

    def do_PUT(self) -> None:
        self._api_or_405()

    def do_DELETE(self) -> None:
        self._api_or_405()

    def do_PATCH(self) -> None:
        self._api_or_405()

    def _api_or_405(self) -> None:
        if urllib.parse.urlsplit(self.path).path.startswith("/api/"):
            self._proxy()
        else:
            self.send_error(405)

    # ── file resolution (nginx try_files + @pages fallback) ───────────────────

    def _resolve(self, url_path: str) -> Path | None:
        clean = posixpath.normpath(urllib.parse.unquote(url_path)).lstrip("/")

        # 1. Fichero directo
        candidate = FRONTEND / clean
        if candidate.is_file():
            return candidate

        # 2. Índice de directorio
        if candidate.is_dir():
            idx = candidate / "index.html"
            if idx.is_file():
                return idx

        # 3. @pages fallback: /pages/<path> y /pages/<path>/index.html
        #    Se evalúa ANTES del SPA fallback para que rutas como /admin/metadata/
        #    resuelvan a pages/admin/metadata/index.html y no a pages/admin/index.html.
        pages = FRONTEND / "pages" / clean
        if pages.is_file():
            return pages
        idx = pages / "index.html"
        if idx.is_file():
            return idx

        # 4. SPA fallback (vanilla): rutas con parámetro en la URL (p.ej. /u/{username}).
        #    Solo aplica cuando el último segmento no tiene extensión de fichero y
        #    no existe una página exacta en pages/ (ya comprobado en el paso 3).
        parts = clean.split("/")
        if len(parts) >= 2 and "." not in parts[-1]:
            spa = FRONTEND / "pages" / parts[0] / "index.html"
            if spa.is_file():
                return spa

        # 5. SPA fallback genérico (build de React, sin pages/): cualquier ruta
        #    sin extensión que no resolvió como fichero sirve el index.html raíz,
        #    dejando que el router client-side decida qué mostrar.
        if "." not in parts[-1] and not (FRONTEND / "pages").is_dir():
            root_index = FRONTEND / "index.html"
            if root_index.is_file():
                return root_index

        return None

    # ── file serving ──────────────────────────────────────────────────────────

    def _serve_file(self, fs: Path, head_only: bool = False) -> None:
        ctype = mimetypes.guess_type(str(fs))[0] or "application/octet-stream"
        try:
            data = fs.read_bytes()
        except OSError:
            self.send_error(403)
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if not head_only:
            self.wfile.write(data)

    # ── redirect helper ───────────────────────────────────────────────────────

    def _redirect(self, location: str, code: int) -> None:
        self.send_response(code)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ── API proxy (con soporte SSE) ────────────────────────────────────────────

    def _proxy(self) -> None:
        url = BACKEND + self.path
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None

        req = urllib.request.Request(url, data=body, method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "content-length", "transfer-encoding"):
                req.add_header(k, v)

        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.end_headers()
                # Stream in chunks — soporta SSE y respuestas grandes
                while True:
                    chunk = resp.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() not in ("transfer-encoding", "connection"):
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_error(502, f"Backend no disponible: {e}")

    # ── logs silenciados ──────────────────────────────────────────────────────

    def log_message(self, fmt: str, *args: object) -> None:
        pass


# ── Server ────────────────────────────────────────────────────────────────────


class _ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    if not FRONTEND.is_dir():
        raise SystemExit(f"[proxy] Frontend no encontrado: {FRONTEND}")
    with _ThreadedServer(("", PORT), DevHandler) as srv:
        print(f"[frontend] http://localhost:{PORT}", flush=True)
        srv.serve_forever()


if __name__ == "__main__":
    main()
