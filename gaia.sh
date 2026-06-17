#!/usr/bin/env bash
# Si se invoca con `sh gaia.sh`, re-ejecutar con bash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
# gaia.sh — gestión de iAgents Hub
# Uso: ./gaia.sh <comando> [--dev] [--local]
#
#   start    Arranca los servicios
#   stop     Detiene los servicios
#   logs     Muestra los logs en tiempo real
#   update   Actualiza a la última versión y reinicia  (solo Docker)
#   status   Estado de los servicios
#
# Flags:
#   --dev    Docker con repos locales (../backend, ../frontend, ../skills)
#   --local  Sin Docker: uvicorn + proxy Python (SQLite, no PostgreSQL)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parseo de flags globales ───────────────────────────────────────────────────
DEV=false
LOCAL=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dev)   DEV=true   ;;
    --local) LOCAL=true ;;
    *)       ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if $DEV && $LOCAL; then
  echo "[gaia] ERROR: --dev y --local son incompatibles." >&2
  exit 1
fi

if $DEV; then
  COMPOSE="docker compose -f docker-compose.yml -f docker-compose.dev.yml"
else
  COMPOSE="docker compose"
fi

# ── Rutas modo local ──────────────────────────────────────────────────────────
LOCAL_DIR="$SCRIPT_DIR/.gaia-local"
BACKEND_PID_FILE="$LOCAL_DIR/backend.pid"
FRONTEND_PID_FILE="$LOCAL_DIR/frontend.pid"
BACKEND_LOG="$LOCAL_DIR/backend.log"
FRONTEND_LOG="$LOCAL_DIR/frontend.log"
VENV_DIR="$SCRIPT_DIR/.venv"
DATA_DIR="$SCRIPT_DIR/data"

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[gaia]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[gaia]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[gaia]${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}[gaia]${RESET} $*" >&2; exit 1; }

# ── Helpers Docker ────────────────────────────────────────────────────────────
check_docker() {
  command -v docker &>/dev/null || error "Docker no está instalado. Descárgalo en https://docs.docker.com/get-docker/"
  docker info &>/dev/null       || error "Docker no está en ejecución. Árrancalo e inténtalo de nuevo."
}

ensure_env() {
  cd "$SCRIPT_DIR"
  if [ ! -f .env ]; then
    cp .env.example .env
    warn "Se ha creado .env a partir de .env.example."
    warn "Edita el fichero .env y cambia las contraseñas antes de continuar."
    echo
    read -rp "¿Has editado .env y quieres continuar? [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]] || { info "Operación cancelada."; exit 0; }
  fi
}

get_port() {
  grep -E '^PORT=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "80"
}

inject_github_token() {
  local token="${GITHUB_TOKEN:-$(grep -E '^GITHUB_TOKEN=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)}"
  [[ -z "$token" ]] && return

  local backend_repo frontend_repo skills_repo agents_repo
  backend_repo="$(grep -E '^BACKEND_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  frontend_repo="$(grep -E '^FRONTEND_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  skills_repo="$(grep -E '^SKILLS_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
  agents_repo="$(grep -E '^AGENTS_REPO=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"

  export BACKEND_REPO="${backend_repo/https:\/\//https://${token}@}"
  export FRONTEND_REPO="${frontend_repo/https:\/\//https://${token}@}"
  export SKILLS_REPO="${skills_repo/https:\/\//https://${token}@}"
  if [[ -n "$agents_repo" ]]; then export AGENTS_REPO="${agents_repo/https:\/\//https://${token}@}"; fi
}

_show_admin_info() {
  local i=0
  while [ $i -lt 30 ]; do
    $COMPOSE exec -T backend sh -c 'exit 0' &>/dev/null && break
    sleep 1; i=$((i+1))
  done

  local admin_email
  admin_email=$($COMPOSE exec -T backend sh -c 'printf "%s" "$GAIA_ADMIN_EMAIL"' 2>/dev/null | tr -d '\r\n') || true
  [ -z "$admin_email" ] && return

  local admin_pass
  admin_pass=$($COMPOSE exec -T backend sh -c 'cat "$GAIA_DATA_DIR/.admin_pass" 2>/dev/null' 2>/dev/null | tr -d '\r\n') || true

  echo
  echo -e "${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}  ║       Acceso de administrador            ║${RESET}"
  echo -e "${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
  echo -e "${BOLD}  ║${RESET}  Email      › ${CYAN}${admin_email}${RESET}"
  if [ -n "$admin_pass" ]; then
    echo -e "${BOLD}  ║${RESET}  Contraseña › ${GREEN}${admin_pass}${RESET}"
  else
    echo -e "${BOLD}  ║${RESET}  Contraseña › (sin cambios)"
  fi
  echo -e "${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
  echo
}

# ── Helpers modo local ────────────────────────────────────────────────────────

check_python() {
  command -v python3 &>/dev/null \
    || error "Python 3 no está instalado. Descárgalo en https://python.org"
  python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)" \
    || error "Se requiere Python 3.8 o superior."
}

ensure_venv() {
  local req="$SCRIPT_DIR/../backend/requirements.txt"
  [ -f "$req" ] || error "No se encontró requirements.txt en ../backend/"

  if [ ! -d "$VENV_DIR" ]; then
    info "Creando entorno virtual en .venv/ ..."
    python3 -m venv "$VENV_DIR"
  fi

  # Reinstalar solo si requirements.txt cambió
  local hash_file="$VENV_DIR/.req_hash"
  local cur_hash="" saved_hash=""
  cur_hash=$(md5 -q "$req" 2>/dev/null \
    || md5sum "$req" 2>/dev/null | cut -d' ' -f1 \
    || echo "")
  [ -f "$hash_file" ] && saved_hash=$(cat "$hash_file")

  if [ "$cur_hash" != "$saved_hash" ]; then
    info "Instalando dependencias Python (puede tardar unos minutos)..."
    "$VENV_DIR/bin/pip" install -q --upgrade pip
    "$VENV_DIR/bin/pip" install -q -r "$req"
    [ -n "$cur_hash" ] && echo "$cur_hash" > "$hash_file"
    success "Dependencias instaladas."
  fi
}

init_local_data() {
  local lang
  lang=$(grep -E '^SKILLS_LANG=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "es")

  mkdir -p "$DATA_DIR/agents/public" "$DATA_DIR/agents/private" \
           "$DATA_DIR/connections"   "$DATA_DIR/memory" \
           "$DATA_DIR/skills/public" "$DATA_DIR/skills/private"

  if [ ! -f "$DATA_DIR/settings.json" ]; then
    local secret
    secret=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 64)
    printf '{"jwt_secret":"%s"}\n' "$secret" > "$DATA_DIR/settings.json"
    info "settings.json creado con secret aleatorio."
  fi

  if [ ! -f "$DATA_DIR/connections/connections.json" ]; then
    printf '[]\n' > "$DATA_DIR/connections/connections.json"
  fi

  # Skills locales (si el directorio existe)
  local skills_repo
  skills_repo=$(grep -E '^DEV_SKILLS_REPO=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "")
  local skills_base="${skills_repo:-$SCRIPT_DIR/../skills}"
  if [ -d "$skills_base/public/$lang" ]; then
    cp -r "$skills_base/public/$lang/." "$DATA_DIR/skills/public/" 2>/dev/null || true
  elif [ -d "$skills_base/public" ]; then
    cp -r "$skills_base/public/." "$DATA_DIR/skills/public/" 2>/dev/null || true
  fi

  # Agentes locales (si el directorio existe)
  local agents_repo
  agents_repo=$(grep -E '^DEV_AGENTS_REPO=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "")
  local agents_base="${agents_repo:-$SCRIPT_DIR/../agents}"
  if [ -d "$agents_base/public/$lang" ]; then
    cp -r "$agents_base/public/$lang/." "$DATA_DIR/agents/public/" 2>/dev/null || true
  elif [ -d "$agents_base/public" ]; then
    cp -r "$agents_base/public/." "$DATA_DIR/agents/public/" 2>/dev/null || true
  fi

  info "Directorio de datos listo: ./data/"
}

_is_running() {
  local pidfile="$1"
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

_kill_pid() {
  local pidfile="$1"
  if [ -f "$pidfile" ]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # Matar hijos (uvicorn --reload lanza un proceso hijo)
      pkill -P "$pid" 2>/dev/null || true
      # Espera breve; SIGKILL si no sale
      local i=0
      while kill -0 "$pid" 2>/dev/null && [ $i -lt 10 ]; do
        sleep 0.3; i=$((i+1))
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
    return 0
  fi
  return 1
}

_local_show_info() {
  # Argumentos opcionales: $1=port $2=gaia_port $3=admin_email
  local port gaia_port admin_email admin_pass
  port="${1:-$(grep -E '^PORT=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "8007")}"
  gaia_port="${2:-$(grep -E '^GAIA_PORT=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "8765")}"
  admin_email="${3:-$(grep -E '^GAIA_ADMIN_EMAIL=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "admin@localhost")}"

  echo
  echo -e "${BOLD}  ╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}  ║       Modo local (sin Docker)            ║${RESET}"
  echo -e "${BOLD}  ╠══════════════════════════════════════════╣${RESET}"
  echo -e "${BOLD}  ║${RESET}  Frontend   › ${CYAN}http://localhost:${port}${RESET}"
  echo -e "${BOLD}  ║${RESET}  Backend    › ${CYAN}http://localhost:${gaia_port}${RESET}"
  echo -e "${BOLD}  ║${RESET}  Admin      › ${CYAN}${admin_email}${RESET}"
  if [ -f "$DATA_DIR/.admin_pass" ]; then
    admin_pass=$(cat "$DATA_DIR/.admin_pass")
    echo -e "${BOLD}  ║${RESET}  Contraseña › ${GREEN}${admin_pass}${RESET}"
  else
    echo -e "${BOLD}  ║${RESET}  Contraseña › (ver logs: ./gaia.sh logs --local)"
  fi
  echo -e "${BOLD}  ║${RESET}  Base datos › ${YELLOW}SQLite — ./data/hub.db${RESET}"
  echo -e "${BOLD}  ╚══════════════════════════════════════════╝${RESET}"
  echo
}

# ── Comandos modo local ───────────────────────────────────────────────────────

cmd_local_start() {
  check_python

  if _is_running "$BACKEND_PID_FILE" || _is_running "$FRONTEND_PID_FILE"; then
    warn "Los servicios locales ya están en ejecución."
    cmd_local_status
    exit 0
  fi

  mkdir -p "$LOCAL_DIR"
  ensure_venv
  init_local_data

  # Leer variables de configuración desde .env (con valores por defecto)
  local port gaia_port admin_email admin_reset agents_secret registration cors_origins
  port=$(grep -E '^PORT=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "8007")
  # En modo local, puertos < 1024 requieren root en macOS/Linux → usar 8007
  if [ "${port:-0}" -lt 1024 ] 2>/dev/null; then
    warn "PORT=${port} requiere privilegios en este sistema. Usando 8007 para modo local."
    warn "Añade 'PORT=8007' (u otro puerto >= 1024) en .env para evitar este aviso."
    port="8007"
  fi
  gaia_port=$(grep -E '^GAIA_PORT=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "8765")
  admin_email=$(grep -E '^GAIA_ADMIN_EMAIL=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "admin@localhost")
  admin_reset=$(grep -E '^GAIA_ADMIN_RESET=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "")
  agents_secret=$(grep -E '^GAIA_AGENTS_SECRET=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "")
  registration=$(grep -E '^GAIA_REGISTRATION=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "open")
  cors_origins=$(grep -E '^GAIA_CORS_ORIGINS=' "$SCRIPT_DIR/.env" 2>/dev/null \
    | cut -d= -f2 | tr -d '"' || echo "http://localhost:$port")

  # ── Backend ──────────────────────────────────────────────────────────────
  info "Arrancando backend en puerto ${gaia_port} ..."
  (
    cd "$SCRIPT_DIR/../backend"
    export GAIA_DATA_DIR="$DATA_DIR"
    export GAIA_HOST="127.0.0.1"
    export GAIA_PORT="$gaia_port"
    export GAIA_RELOAD="true"
    export GAIA_REGISTRATION="$registration"
    export GAIA_ADMIN_EMAIL="$admin_email"
    export GAIA_ADMIN_RESET="$admin_reset"
    export GAIA_AGENTS_SECRET="$agents_secret"
    export GAIA_CORS_ORIGINS="$cors_origins"
    export GAIA_EMAIL_VERIFY="false"
    export GAIA_SMTP_HOST=""
    export DATABASE_URL=""
    exec "$VENV_DIR/bin/python" main.py
  ) >> "$BACKEND_LOG" 2>&1 &
  echo $! > "$BACKEND_PID_FILE"

  # ── Frontend proxy ───────────────────────────────────────────────────────
  info "Arrancando frontend proxy en puerto ${port} ..."
  (
    export PORT="$port"
    export GAIA_PORT="$gaia_port"
    exec "$VENV_DIR/bin/python" "$SCRIPT_DIR/local_proxy.py"
  ) >> "$FRONTEND_LOG" 2>&1 &
  echo $! > "$FRONTEND_PID_FILE"

  success "Servicios locales arrancados."
  _local_show_info "$port" "$gaia_port" "$admin_email"
  info "Logs → ./gaia.sh logs --local   |   Para detener → ./gaia.sh stop --local"
}

cmd_local_stop() {
  local stopped=false
  _kill_pid "$BACKEND_PID_FILE"  && { info "Backend detenido.";  stopped=true; }
  _kill_pid "$FRONTEND_PID_FILE" && { info "Frontend detenido."; stopped=true; }
  $stopped \
    && success "Servicios locales detenidos." \
    || info "No había servicios locales en ejecución."
}

cmd_local_status() {
  echo
  for svc in backend frontend; do
    local pf="$LOCAL_DIR/$svc.pid"
    if [ -f "$pf" ]; then
      local pid; pid=$(cat "$pf")
      if kill -0 "$pid" 2>/dev/null; then
        echo -e "  ${GREEN}●${RESET} $svc (PID $pid) — en ejecución"
      else
        echo -e "  ${RED}●${RESET} $svc (PID $pid) — detenido (PID obsoleto)"
        rm -f "$pf"
      fi
    else
      echo -e "  ${RED}●${RESET} $svc — no iniciado"
    fi
  done
  echo
}

cmd_local_logs() {
  mkdir -p "$LOCAL_DIR"
  touch "$BACKEND_LOG" "$FRONTEND_LOG"
  info "Mostrando logs (Ctrl+C para salir)..."
  tail -f "$BACKEND_LOG" "$FRONTEND_LOG"
}

# ── Comandos Docker ───────────────────────────────────────────────────────────

cmd_start() {
  check_docker
  ensure_env
  cd "$SCRIPT_DIR"
  inject_github_token
  if $DEV; then info "Modo desarrollo — usando repos locales"; fi
  info "Construyendo e iniciando servicios..."
  $COMPOSE rm -f data-init 2>/dev/null || true
  $COMPOSE up -d --build
  PORT=$(get_port)
  echo
  success "iAgents Hub en marcha → http://localhost:${PORT}"
  _show_admin_info
}

cmd_stop() {
  check_docker
  cd "$SCRIPT_DIR"
  info "Deteniendo servicios..."
  $COMPOSE down
  success "Servicios detenidos."
}

cmd_logs() {
  check_docker
  cd "$SCRIPT_DIR"
  info "Mostrando logs (Ctrl+C para salir)..."
  $COMPOSE logs -f --tail=100
}

cmd_update() {
  check_docker
  ensure_env
  cd "$SCRIPT_DIR"
  inject_github_token
  if $DEV; then info "Modo desarrollo — usando repos locales"; fi
  info "Actualizando a la última versión..."
  $COMPOSE rm -f data-init 2>/dev/null || true
  $COMPOSE down
  $COMPOSE up -d --build
  PORT=$(get_port)
  echo
  success "Actualización completada → http://localhost:${PORT}"
  _show_admin_info
}

cmd_status() {
  check_docker
  cd "$SCRIPT_DIR"
  $COMPOSE ps
}

# ── Main ──────────────────────────────────────────────────────────────────────

if $LOCAL; then
  case "${1:-}" in
    start)  cmd_local_start  ;;
    stop)   cmd_local_stop   ;;
    logs)   cmd_local_logs   ;;
    status) cmd_local_status ;;
    *)
      echo -e "${BOLD}Uso:${RESET} ./gaia.sh <comando> --local"
      echo
      echo "  start    Arranca backend (uvicorn) y frontend (proxy Python) sin Docker"
      echo "  stop     Detiene los servicios locales"
      echo "  logs     Muestra los logs en tiempo real"
      echo "  status   Estado de los procesos locales"
      echo
      echo -e "  ${YELLOW}Base de datos: SQLite en ./data/hub.db  (con persistencia)${RESET}"
      echo -e "  ${YELLOW}Sin PostgreSQL ni contenedores Docker.${RESET}"
      echo
      exit 1
      ;;
  esac
else
  case "${1:-}" in
    start)  cmd_start  ;;
    stop)   cmd_stop   ;;
    logs)   cmd_logs   ;;
    update) cmd_update ;;
    status) cmd_status ;;
    *)
      echo -e "${BOLD}Uso:${RESET} ./gaia.sh <comando> [--dev] [--local]"
      echo
      echo "  start    Arranca los servicios"
      echo "  stop     Detiene los servicios"
      echo "  logs     Muestra los logs en tiempo real"
      echo "  update   Actualiza a la última versión y reinicia"
      echo "  status   Estado de los contenedores"
      echo
      echo -e "${BOLD}Flags:${RESET}"
      echo "  --dev    Usa repos locales (../backend, ../frontend, ../skills) en lugar de GitHub"
      echo "  --local  Sin Docker: uvicorn + proxy Python (SQLite, sin PostgreSQL)"
      echo
      exit 1
      ;;
  esac
fi
