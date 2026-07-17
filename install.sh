#!/usr/bin/env bash
# install.sh — Instalación y actualización de iAgents Hub (Linux / macOS)
#
# Un único comando para las 4 combinaciones posibles: el script pregunta
# qué frontend (Vanilla o React) y qué modo (Docker o sin Docker) instalar.
#
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash
#
# Para saltarte los prompts (CI, scripts, reinstalación no interactiva):
#   IAGENTSHUB_FRONTEND=vanilla|react  IAGENTSHUB_MODE=docker|local  bash install.sh
#
# Docker:     solo requiere Docker. No clona repositorios (usa imágenes de Docker Hub).
# Sin Docker: instala Python 3.11+, git y (si eliges React) Node.js LTS mediante el
#             gestor de paquetes nativo del sistema (apt/dnf/yum/pacman/zypper/Homebrew),
#             clona los repos como hermanos y arranca con gaia.py --local (SQLite).

set -euo pipefail

# ── Colores ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
  RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; RED=''; BOLD=''; RESET=''
fi

info()    { echo -e "${CYAN}${BOLD}[iagentshub]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[iagentshub]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[iagentshub]${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}[iagentshub]${RESET} $*" >&2; exit 1; }
step()    { echo; echo -e "${BOLD}── $* ──────────────────────────────────────${RESET}"; }

# ── Ayuda ──────────────────────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help|help)
    cat <<EOF
${BOLD}Uso:${RESET} install.sh

Instala o actualiza iAgents Hub. Pregunta interactivamente:
  1) Frontend: Vanilla (estático) o React (SPA, requiere Node.js)
  2) Modo: Docker (recomendado) o sin Docker (Python/Node directos, SQLite)

${BOLD}Variables de entorno${RESET} (para saltarte los prompts):
  IAGENTSHUB_FRONTEND=vanilla|react   Frontend a instalar
  IAGENTSHUB_MODE=docker|local        Modo de instalación
  IAGENTSHUB_DIR=<ruta>               Directorio de instalación (default: \$HOME/iagentshub)

${BOLD}Ejemplos:${RESET}
  curl -fsSL ${GITHUB_RAW:-https://raw.githubusercontent.com/iagentshub/iAgents/main}/install.sh | bash
  IAGENTSHUB_FRONTEND=vanilla IAGENTSHUB_MODE=docker bash install.sh

${BOLD}Requisitos:${RESET}
  Docker:     solo Docker (no clona repositorios, usa imágenes de Docker Hub).
  Sin Docker: instala Python 3.11+, git y (si eliges React) Node.js LTS mediante
              el gestor de paquetes nativo del sistema.
EOF
    exit 0
    ;;
esac

# ── Detección de sistema operativo ────────────────────────────────────────────
IS_MAC=false
IS_LINUX=false
case "$(uname -s)" in
  Darwin) IS_MAC=true ;;
  Linux)  IS_LINUX=true ;;
  *) error "SO no soportado por este script. En Windows usa: irm https://raw.githubusercontent.com/iagentshub/iAgents/main/install.ps1 | iex" ;;
esac

REPO_URL="https://github.com/iagentshub/iAgents.git"
BACKEND_REPO_URL="https://github.com/iagentshub/backend_fastapi.git"
FRONTEND_VANILLA_URL="https://github.com/iagentshub/frontend_vanilla.git"
FRONTEND_REACT_URL="https://github.com/iagentshub/frontend_react.git"
GITHUB_RAW="https://raw.githubusercontent.com/iagentshub/iAgents/main"
COMPOSE_URL="${GITHUB_RAW}/docker-compose.hub.yml"
INSTALL_DIR="${IAGENTSHUB_DIR:-$HOME/iagentshub}"
MIN_PYTHON="3.11"

# Generador de hex aleatorio compatible con macOS y Linux
_rand_hex() {
  LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 64 \
    || python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null \
    || date +%s%N | sha256sum | head -c 64
}

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║           iAgents Hub                   ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo

# ── Prompt 1: frontend ────────────────────────────────────────────────────────
step "Frontend"
echo "  1) Vanilla  — estático, sin build, más ligero (recomendado)"
echo "  2) React    — SPA nueva, en migración (requiere Node.js)"
FRONTEND_ANSWER=""
if [ -t 0 ] && [ -z "${IAGENTSHUB_FRONTEND:-}" ]; then
  read -rp "  Elige [1-2] (default 1): " FRONTEND_ANSWER
fi
FRONTEND_VARIANT="${IAGENTSHUB_FRONTEND:-}"
if [ -z "$FRONTEND_VARIANT" ]; then
  case "$FRONTEND_ANSWER" in
    2) FRONTEND_VARIANT="react" ;;
    *) FRONTEND_VARIANT="vanilla" ;;
  esac
fi
[ "$FRONTEND_VARIANT" = "vanilla" ] || [ "$FRONTEND_VARIANT" = "react" ] \
  || error "IAGENTSHUB_FRONTEND debe ser 'vanilla' o 'react' (valor: ${FRONTEND_VARIANT})"
success "Frontend: ${FRONTEND_VARIANT}"

# ── Prompt 2: modo de instalación ─────────────────────────────────────────────
step "Modo de instalación"
echo "  1) Docker      — recomendado, aislado, incluye PostgreSQL opcional"
if [ "$FRONTEND_VARIANT" = "react" ]; then
  echo "  2) Sin Docker  — Python + Node.js directos, SQLite"
else
  echo "  2) Sin Docker  — Python directo, SQLite"
fi
MODE_ANSWER=""
if [ -t 0 ] && [ -z "${IAGENTSHUB_MODE:-}" ]; then
  read -rp "  Elige [1-2] (default 1): " MODE_ANSWER
fi
INSTALL_MODE="${IAGENTSHUB_MODE:-}"
if [ -z "$INSTALL_MODE" ]; then
  case "$MODE_ANSWER" in
    2) INSTALL_MODE="local" ;;
    *) INSTALL_MODE="docker" ;;
  esac
fi
[ "$INSTALL_MODE" = "docker" ] || [ "$INSTALL_MODE" = "local" ] \
  || error "IAGENTSHUB_MODE debe ser 'docker' o 'local' (valor: ${INSTALL_MODE})"
success "Modo: ${INSTALL_MODE}$([ "$INSTALL_MODE" = docker ] && echo ' (Docker)' || echo ' (sin Docker)')"

# ═══════════════════════════════════════════════════════════════════════════
# Rama Docker
# ═══════════════════════════════════════════════════════════════════════════
install_docker() {
  COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

  step "Comprobando dependencias"
  command -v docker &>/dev/null \
    || error "Docker no está instalado. Instálalo en: https://docs.docker.com/get-docker/"
  docker info &>/dev/null \
    || error "Docker no está en ejecución o no tienes permisos. Prueba: sudo usermod -aG docker \$USER"
  command -v curl &>/dev/null \
    || error "curl no está instalado (apt install curl / brew install curl)."

  mkdir -p "${INSTALL_DIR}"
  cd "${INSTALL_DIR}"

  FIRST_INSTALL=true
  [ -f .env ] && FIRST_INSTALL=false

  if $FIRST_INSTALL; then
    info "Primera instalación en ${INSTALL_DIR}"
  else
    info "Actualización detectada en ${INSTALL_DIR}"
  fi

  info "Sincronizando docker-compose.yml desde GitHub..."
  curl -fsSL "${COMPOSE_URL}" -o docker-compose.yml
  success "docker-compose.yml actualizado."

  IMAGE_TAG_DEFAULT="latest"
  [ "$FRONTEND_VARIANT" = "vanilla" ] && IMAGE_TAG_DEFAULT="vanilla"

  if $FIRST_INSTALL; then
    step "Configurando variables de entorno"
    echo

    if [ -t 0 ]; then
      read -rp "  Dominio público (ej: https://miapp.com) [http://localhost:8007]: " INPUT_URL
      read -rp "  Email del administrador [admin@localhost]: " INPUT_EMAIL
      read -rp "  Puerto del frontend [8007]: " INPUT_PORT
    fi
    FRONTEND_URL="${INPUT_URL:-http://localhost:8007}"
    ADMIN_EMAIL="${INPUT_EMAIL:-admin@localhost}"
    PORT="${INPUT_PORT:-8007}"

    AGENTS_SECRET=$(_rand_hex)
    DB_PASSWORD=$(_rand_hex)

    cat > .env <<EOF
# iAgents Hub — configuración generada el $(date '+%Y-%m-%d')
# Para cambiar la configuración edita este fichero y ejecuta:
#   cd ${INSTALL_DIR} && docker compose up -d

PORT=${PORT}
GAIA_PORT=8765
GAIA_FRONTEND_URL=${FRONTEND_URL}

# Secreto JWT — generado automáticamente, no lo cambies salvo que reinicies desde cero
GAIA_AGENTS_SECRET=${AGENTS_SECRET}

GAIA_ADMIN_EMAIL=${ADMIN_EMAIL}
# Descomenta para resetear la contraseña del admin en el próximo arranque (quitar después)
# GAIA_ADMIN_RESET=true

# open | invite | closed
GAIA_REGISTRATION=closed
GAIA_EMAIL_VERIFY=false

# ── SMTP ─────────────────────────────────────────────────────────────────────
# Vacío = desactivado (los tokens de reset se muestran en: docker logs iagentshub-iagentshub-1)
GAIA_SMTP_HOST=
GAIA_SMTP_PORT=587
GAIA_SMTP_TLS=starttls
GAIA_SMTP_USER=
GAIA_SMTP_PASS=
GAIA_SMTP_FROM=
GAIA_WEBMAIL_URL=
GAIA_RESET_EXPIRE_HOURS=1

GAIA_MAX_GUEST_SESSIONS=0

# ── Base de datos ─────────────────────────────────────────────────────────────
# Vacío = SQLite en /data/hub.db (recomendado para empezar)
# PostgreSQL: postgresql://gaia:<GAIA_DB_PASSWORD>@postgres:5432/iagentshub
DATABASE_URL=
GAIA_DB_PASSWORD=${DB_PASSWORD}

# ── Stripe (opcional) ─────────────────────────────────────────────────────────
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=

# ── Docker Hub ────────────────────────────────────────────────────────────────
DOCKER_HUB_USER=iagenthub
# latest = React · vanilla = Vanilla — fijado según el frontend elegido en la instalación
IMAGE_TAG=${IMAGE_TAG_DEFAULT}

GAIA_TRUSTED_PROXIES=127.0.0.1
EOF

    success ".env creado."
  else
    warn ".env existente conservado. Edita ${INSTALL_DIR}/.env para cambiar la configuración."
  fi

  echo
  if $FIRST_INSTALL; then
    info "Descargando imágenes de Docker Hub..."
  else
    info "Descargando imágenes actualizadas de Docker Hub..."
    docker compose -f "${COMPOSE_FILE}" down
  fi

  docker compose -f "${COMPOSE_FILE}" pull
  docker compose -f "${COMPOSE_FILE}" up -d

  info "Esperando que el backend arranque..."
  MAX=40
  I=0
  while true; do
    if docker compose -f "${COMPOSE_FILE}" exec -T iagentshub \
        sh -c 'test -f /data/.admin_pass' </dev/null &>/dev/null; then
      break
    fi
    I=$((I+1))
    if [ "$I" -ge "$MAX" ]; then
      warn "Timeout esperando .admin_pass (el backend puede tardar más en arrancar)"
      break
    fi
    sleep 3
  done

  ADMIN_PASS=$(docker compose -f "${COMPOSE_FILE}" exec -T iagentshub \
    sh -c 'cat /data/.admin_pass' </dev/null 2>/dev/null | tr -d '\r\n' || true)

  # shellcheck disable=SC1091
  source "${INSTALL_DIR}/.env" 2>/dev/null || true

  echo
  if $FIRST_INSTALL; then
    echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║       Instalación completada ✓           ║${RESET}"
    echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
  else
    echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║       Actualización completada ✓         ║${RESET}"
    echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
  fi
  echo -e "${BOLD}║${RESET}  URL         › ${CYAN}${GAIA_FRONTEND_URL:-http://localhost:${PORT:-8007}}${RESET}"
  echo -e "${BOLD}║${RESET}  Frontend    › ${CYAN}${FRONTEND_VARIANT}${RESET}"
  echo -e "${BOLD}║${RESET}  Admin       › ${CYAN}${GAIA_ADMIN_EMAIL:-admin@localhost}${RESET}"
  if [ -n "${ADMIN_PASS:-}" ]; then
    echo -e "${BOLD}║${RESET}  Contraseña  › ${GREEN}${ADMIN_PASS}${RESET}"
  else
    echo -e "${BOLD}║${RESET}  Contraseña  › ${YELLOW}ver: docker logs iagentshub-iagentshub-1 | grep -i pass${RESET}"
  fi
  echo -e "${BOLD}║${RESET}  Directorio  › ${INSTALL_DIR}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
  echo
  echo -e "  Logs:        ${CYAN}cd ${INSTALL_DIR} && docker compose logs -f${RESET}"
  echo -e "  Parar:       ${CYAN}cd ${INSTALL_DIR} && docker compose down${RESET}"
  echo -e "  Actualizar:  ${CYAN}curl -fsSL ${GITHUB_RAW}/install.sh | bash${RESET}"
  echo
}

# ═══════════════════════════════════════════════════════════════════════════
# Rama sin Docker
# ═══════════════════════════════════════════════════════════════════════════

# sudo solo si hace falta (algunos contenedores/CI ya corren como root)
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo &>/dev/null && SUDO="sudo"
fi

PKG_MANAGER=""
PKG_INSTALL=""
_detect_pkg_manager() {
  [ -n "$PKG_MANAGER" ] && return 0
  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt-get"; PKG_INSTALL="$SUDO apt-get install -y"
    $SUDO apt-get update -y -qq || true
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"; PKG_INSTALL="$SUDO dnf install -y"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"; PKG_INSTALL="$SUDO yum install -y"
  elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"; PKG_INSTALL="$SUDO pacman -S --noconfirm"
  elif command -v zypper &>/dev/null; then
    PKG_MANAGER="zypper"; PKG_INSTALL="$SUDO zypper install -y"
  else
    error "No se encontró un gestor de paquetes soportado (apt-get, dnf, yum, pacman, zypper). Instala Python ${MIN_PYTHON}+, git y Node.js manualmente y vuelve a ejecutar este script."
  fi
  info "Gestor de paquetes detectado: ${PKG_MANAGER}"
}

_find_python() {
  local candidate
  for candidate in python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" &>/dev/null; then
      if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
        echo "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

_clone_or_update() {
  local url="$1" dir="$2" name="$3"
  if [ -d "${dir}/.git" ]; then
    info "Actualizando ${name}..."
    git -C "${dir}" pull --ff-only
  else
    info "Clonando ${name}..."
    git clone "${url}" "${dir}"
  fi
}

install_local() {
  # ── Detectar si es actualización ─────────────────────────────────────────
  FIRST_INSTALL=true
  [ -f "${INSTALL_DIR}/iAgents/.env" ] && FIRST_INSTALL=false

  # ── 1. Homebrew (solo macOS) ──────────────────────────────────────────────
  if $IS_MAC; then
    step "Comprobando Homebrew"
    if ! command -v brew &>/dev/null; then
      info "Instalando Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
      success "Homebrew instalado."
    else
      success "Homebrew ya instalado: $(brew --version | head -1)"
    fi
  fi

  # ── 2. Python ≥ 3.11 ──────────────────────────────────────────────────────
  step "Comprobando Python ${MIN_PYTHON}+"
  PYTHON="$(_find_python || true)"

  if [ -z "$PYTHON" ]; then
    info "Python ${MIN_PYTHON}+ no encontrado. Instalando..."
    if $IS_MAC; then
      brew install python@3.11
      PYTHON="$(brew --prefix)/bin/python3.11"
    else
      _detect_pkg_manager
      case "$PKG_MANAGER" in
        apt-get)
          $PKG_INSTALL python3.11 python3.11-venv 2>/dev/null \
            || $PKG_INSTALL python3 python3-venv python3-pip
          ;;
        dnf|yum)
          $PKG_INSTALL python3.11 python3.11-pip 2>/dev/null \
            || $PKG_INSTALL python3 python3-pip
          ;;
        pacman)
          $PKG_INSTALL python python-pip
          ;;
        zypper)
          $PKG_INSTALL python311 python311-pip 2>/dev/null \
            || $PKG_INSTALL python3 python3-pip
          ;;
      esac
      PYTHON="$(_find_python || true)"
    fi
    [ -n "$PYTHON" ] || error "No se pudo instalar Python ${MIN_PYTHON}+ automáticamente. Instálalo manualmente (p.ej. desde https://python.org) y vuelve a ejecutar este script."
    success "Python instalado: $($PYTHON --version)"
  else
    success "Python encontrado: $($PYTHON --version)"
  fi

  # Algunas distros (Debian/Ubuntu) separan el módulo venv del paquete base.
  if $IS_LINUX && ! "$PYTHON" -c "import venv" 2>/dev/null; then
    info "Instalando soporte de entornos virtuales (venv)..."
    _detect_pkg_manager
    case "$PKG_MANAGER" in
      apt-get) $PKG_INSTALL python3-venv ;;
      *) : ;;
    esac
  fi

  # ── 3. Git ────────────────────────────────────────────────────────────────
  step "Comprobando git"
  if ! command -v git &>/dev/null; then
    info "Instalando git..."
    if $IS_MAC; then
      brew install git
    else
      _detect_pkg_manager
      $PKG_INSTALL git
    fi
    success "git instalado."
  else
    success "git ya instalado: $(git --version)"
  fi

  # ── 4. Node.js (solo si el frontend elegido es React) ────────────────────
  if [ "$FRONTEND_VARIANT" = "react" ]; then
    step "Comprobando Node.js"
    if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
      info "Node.js no encontrado. Instalando..."
      if $IS_MAC; then
        brew install node
      else
        _detect_pkg_manager
        case "$PKG_MANAGER" in
          apt-get) $PKG_INSTALL nodejs npm ;;
          dnf|yum) $PKG_INSTALL nodejs npm ;;
          pacman)  $PKG_INSTALL nodejs npm ;;
          zypper)  $PKG_INSTALL nodejs20 npm20 2>/dev/null || $PKG_INSTALL nodejs npm ;;
        esac
      fi
      command -v node &>/dev/null || error "No se pudo instalar Node.js automáticamente. Instálalo manualmente desde https://nodejs.org y vuelve a ejecutar este script."
      success "Node.js instalado: $(node --version)"
    else
      success "Node.js encontrado: $(node --version)"
    fi
  fi

  # ── 5. Clonar o actualizar repositorios ───────────────────────────────────
  # iagentshub/backend_fastapi/frontend_{vanilla,react} son repos separados que
  # deben quedar como hermanos dentro de INSTALL_DIR — gaia.py (dentro de
  # iAgents/) resuelve ../backend_fastapi y ../frontend_<variante> de forma
  # relativa, y espera este layout exacto.
  step "Repositorios"
  mkdir -p "${INSTALL_DIR}"

  if [ "$FRONTEND_VARIANT" = "react" ]; then
    FRONTEND_REPO_URL="$FRONTEND_REACT_URL"
    FRONTEND_DIRNAME="frontend_react"
  else
    FRONTEND_REPO_URL="$FRONTEND_VANILLA_URL"
    FRONTEND_DIRNAME="frontend_vanilla"
  fi

  _clone_or_update "${REPO_URL}"          "${INSTALL_DIR}/iAgents"                "iagentshub"
  _clone_or_update "${BACKEND_REPO_URL}"  "${INSTALL_DIR}/backend_fastapi"        "backend"
  _clone_or_update "${FRONTEND_REPO_URL}" "${INSTALL_DIR}/${FRONTEND_DIRNAME}"    "frontend (${FRONTEND_VARIANT})"
  success "Repositorios listos."

  # El entorno virtual/dependencias Python y el build de React los gestiona
  # gaia.py por su cuenta (ensure_venv / ensure_frontend_build) al arrancar
  # en el paso siguiente — no lo dupliques aquí.

  # ── 6. Configurar .env ────────────────────────────────────────────────────
  ENV_FILE="${INSTALL_DIR}/iAgents/.env"
  if $FIRST_INSTALL; then
    step "Configuración inicial"
    echo

    if [ -t 0 ]; then
      read -rp "  Email del administrador [admin@localhost]: " INPUT_EMAIL
      read -rp "  Puerto [8007]: " INPUT_PORT
    fi
    ADMIN_EMAIL="${INPUT_EMAIL:-admin@localhost}"
    PORT="${INPUT_PORT:-8007}"

    SECRET=$("$PYTHON" -c "import secrets; print(secrets.token_hex(32))")

    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" <<EOF
# iAgents Hub — configuración generada el $(date '+%Y-%m-%d')
# Edita este fichero y ejecuta: python3 gaia.py start --local

PORT=${PORT}
GAIA_PORT=8765
GAIA_FRONTEND_URL=http://localhost:${PORT}

# vanilla | react — fijado según lo elegido en la instalación
GAIA_FRONTEND_VARIANT=${FRONTEND_VARIANT}

# Secreto JWT — generado automáticamente
GAIA_AGENTS_SECRET=${SECRET}

GAIA_ADMIN_EMAIL=${ADMIN_EMAIL}
# Descomenta para resetear la contraseña del admin en el próximo arranque:
# GAIA_ADMIN_RESET=true

# open | invite | closed
GAIA_REGISTRATION=closed
GAIA_EMAIL_VERIFY=false

# ── SMTP (opcional) ───────────────────────────────────────────────────────────
GAIA_SMTP_HOST=
GAIA_SMTP_PORT=587
GAIA_SMTP_TLS=starttls
GAIA_SMTP_USER=
GAIA_SMTP_PASS=
GAIA_SMTP_FROM=
GAIA_RESET_EXPIRE_HOURS=1

GAIA_MAX_GUEST_SESSIONS=200
GAIA_DATA_DIR=${INSTALL_DIR}/iAgents/data

# SQLite (por defecto) — para PostgreSQL: postgresql://user:pass@host:5432/db
DATABASE_URL=
EOF
    success ".env creado."
  else
    warn ".env existente conservado (${ENV_FILE})."
    # Instalaciones previas a esta versión no tienen GAIA_FRONTEND_VARIANT —
    # añadirla si falta, respetando el frontend clonado en este mismo run.
    if ! grep -q '^GAIA_FRONTEND_VARIANT=' "$ENV_FILE" 2>/dev/null; then
      echo "GAIA_FRONTEND_VARIANT=${FRONTEND_VARIANT}" >> "$ENV_FILE"
      info "GAIA_FRONTEND_VARIANT=${FRONTEND_VARIANT} añadido a .env"
    fi
  fi

  # ── 7. Arrancar ───────────────────────────────────────────────────────────
  step "Arrancando iAgents Hub"
  cd "${INSTALL_DIR}/iAgents"
  "$PYTHON" gaia.py start --local

  # ── Resumen ───────────────────────────────────────────────────────────────
  source "${ENV_FILE}" 2>/dev/null || true
  ADMIN_PASS_FILE="${INSTALL_DIR}/iAgents/data/.admin_pass"
  ADMIN_PASS=""
  for i in $(seq 1 15); do
    if [ -f "$ADMIN_PASS_FILE" ]; then
      ADMIN_PASS=$(cat "$ADMIN_PASS_FILE" 2>/dev/null || true)
      break
    fi
    sleep 2
  done

  echo
  if $FIRST_INSTALL; then
    echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║       Instalación completada ✓           ║${RESET}"
    echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
  else
    echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║       Actualización completada ✓         ║${RESET}"
    echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
  fi
  echo -e "${BOLD}║${RESET}  URL         › ${CYAN}http://localhost:${PORT:-8007}${RESET}"
  echo -e "${BOLD}║${RESET}  Frontend    › ${CYAN}${FRONTEND_VARIANT}${RESET}"
  echo -e "${BOLD}║${RESET}  Admin       › ${CYAN}${GAIA_ADMIN_EMAIL:-admin@localhost}${RESET}"
  if [ -n "${ADMIN_PASS}" ]; then
    echo -e "${BOLD}║${RESET}  Contraseña  › ${GREEN}${ADMIN_PASS}${RESET}"
  else
    echo -e "${BOLD}║${RESET}  Contraseña  › ${YELLOW}ver: ${INSTALL_DIR}/iAgents/data/.admin_pass${RESET}"
  fi
  echo -e "${BOLD}║${RESET}  Directorio  › ${INSTALL_DIR}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
  echo
  echo -e "  Parar:       ${CYAN}cd ${INSTALL_DIR}/iAgents && python3 gaia.py stop --local${RESET}"
  echo -e "  Logs:        ${CYAN}cd ${INSTALL_DIR}/iAgents && python3 gaia.py logs --local${RESET}"
  echo -e "  Actualizar:  ${CYAN}curl -fsSL ${GITHUB_RAW}/install.sh | bash${RESET}"
  echo -e "  Arrancar:    ${CYAN}cd ${INSTALL_DIR}/iAgents && python3 gaia.py start --local${RESET}"
  echo
}

# ── Main ──────────────────────────────────────────────────────────────────────
if [ "$INSTALL_MODE" = "docker" ]; then
  install_docker
else
  install_local
fi
