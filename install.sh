#!/usr/bin/env bash
# install.sh — Instalación y actualización de iAgents Hub (Linux / macOS)
#
# Un único comando para instalar la plataforma completa (backend FastAPI y
# frontend React) en Docker o sin Docker.
#
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iAgents/main/install.sh | bash
#
# Para saltarte los prompts (CI, scripts, reinstalación no interactiva):
#   IAGENTSHUB_MODE=docker|local  bash install.sh
#
# Docker:     solo requiere Docker. No clona repositorios (usa imágenes de GHCR).
# Sin Docker: instala Python 3.11+, git y Node.js LTS mediante el
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

Instala o actualiza iAgents Hub completo (backend y frontends). Pregunta interactivamente:
  1) Modo: Docker (recomendado) o sin Docker (Python/Node directos, SQLite)

${BOLD}Variables de entorno${RESET} (para saltarte los prompts):
  IAGENTSHUB_MODE=docker|local        Modo de instalación
  IAGENTSHUB_COMPONENT=full|backend|frontend
                                      Componentes que se instalarán
  IAGENTSHUB_API_URL=<url>            Backend remoto para frontend aislado
  IAGENTSHUB_DIR=<ruta>               Directorio de instalación (default: \$HOME/iagentshub)

${BOLD}Ejemplos:${RESET}
  curl -fsSL ${GITHUB_RAW:-https://raw.githubusercontent.com/iagentshub/iAgents/main}/install.sh | bash
  IAGENTSHUB_MODE=docker bash install.sh

${BOLD}Requisitos:${RESET}
  Docker:     solo Docker (no clona repositorios, usa imágenes de GitHub Container Registry).
  Sin Docker: instala Python 3.11+, git y Node.js LTS mediante
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
FRONTEND_REACT_URL="https://github.com/iagentshub/frontend_react.git"
GITHUB_RAW="https://raw.githubusercontent.com/iagentshub/iAgents/main"
INSTALL_DIR="${IAGENTSHUB_DIR:-$HOME/iagentshub}"
MIN_PYTHON="3.11"

# Generador de hex aleatorio compatible con macOS y Linux
_rand_hex() {
  LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 64 \
    || python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null \
    || date +%s%N | sha256sum | head -c 64
}

CAN_PROMPT=false
if { [ -t 0 ] || [ -t 1 ]; } && [ -r /dev/tty ] && [ -w /dev/tty ]; then
  CAN_PROMPT=true
fi

_prompt() {
  local message="$1" variable="$2"
  if $CAN_PROMPT; then
    local answer=""
    printf '%s' "$message" >/dev/tty
    IFS= read -r answer </dev/tty
    printf -v "$variable" '%s' "$answer"
  fi
}

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║           iAgents Hub                   ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo

# ── Modo de instalación ───────────────────────────────────────────────────────
step "Modo de instalación"
echo "  1) Docker      — recomendado, aislado, incluye PostgreSQL opcional"
echo "  2) Sin Docker  — Python + Node.js directos, SQLite"
MODE_ANSWER=""
MODE_FILE="${INSTALL_DIR}/.install-mode"
DETECTED_MODE=""
if [ -f "$MODE_FILE" ]; then
  DETECTED_MODE="$(tr -d '[:space:]' < "$MODE_FILE")"
elif [ -f "${INSTALL_DIR}/.env" ]; then
  DETECTED_MODE="docker"
elif [ -f "${INSTALL_DIR}/iAgents/.env" ]; then
  DETECTED_MODE="local"
fi
if [ -z "${IAGENTSHUB_MODE:-}" ] && [ -z "$DETECTED_MODE" ]; then
  _prompt "  Elige [1-2] (default 1): " MODE_ANSWER
fi

# ── Componentes ──────────────────────────────────────────────────────────────
step "Componentes"
echo "  1) Aplicación completa — backend + frontend"
echo "  2) Solo backend"
echo "  3) Solo frontend    — requiere la URL de un backend"
COMPONENT_ANSWER=""
COMPONENT_FILE="${INSTALL_DIR}/.install-component"
DETECTED_COMPONENT=""
if [ -f "$COMPONENT_FILE" ]; then
  DETECTED_COMPONENT="$(tr -d '[:space:]' < "$COMPONENT_FILE")"
elif [ -n "$DETECTED_MODE" ]; then
  DETECTED_COMPONENT="full"
fi
if [ -z "${IAGENTSHUB_COMPONENT:-}" ] && [ -z "$DETECTED_COMPONENT" ]; then
  _prompt "  Elige [1-3] (default 1): " COMPONENT_ANSWER
fi
INSTALL_COMPONENT="${IAGENTSHUB_COMPONENT:-$DETECTED_COMPONENT}"
if [ -z "$INSTALL_COMPONENT" ]; then
  case "$COMPONENT_ANSWER" in
    2) INSTALL_COMPONENT="backend" ;;
    3) INSTALL_COMPONENT="frontend" ;;
    *) INSTALL_COMPONENT="full" ;;
  esac
fi
case "$INSTALL_COMPONENT" in
  full)
    COMPOSE_URL="${GITHUB_RAW}/docker-compose.hub.yml"
    IMAGE_REPOSITORY="ghcr.io/iagentshub/app"
    ;;
  backend)
    COMPOSE_URL="${GITHUB_RAW}/docker-compose.backend.yml"
    IMAGE_REPOSITORY="ghcr.io/iagentshub/backend"
    ;;
  frontend)
    COMPOSE_URL="${GITHUB_RAW}/docker-compose.frontend.yml"
    IMAGE_REPOSITORY="ghcr.io/iagentshub/frontend"
    ;;
  *) error "IAGENTSHUB_COMPONENT debe ser full, backend o frontend (valor: ${INSTALL_COMPONENT})" ;;
esac
success "Componentes: ${INSTALL_COMPONENT}"
if [ -n "$DETECTED_COMPONENT" ] && [ -z "${IAGENTSHUB_COMPONENT:-}" ]; then
  info "Componentes de la instalación existente detectados automáticamente."
fi
INSTALL_MODE="${IAGENTSHUB_MODE:-$DETECTED_MODE}"
if [ -z "$INSTALL_MODE" ]; then
  case "$MODE_ANSWER" in
    2) INSTALL_MODE="local" ;;
    *) INSTALL_MODE="docker" ;;
  esac
fi
[ "$INSTALL_MODE" = "docker" ] || [ "$INSTALL_MODE" = "local" ] \
  || error "IAGENTSHUB_MODE debe ser 'docker' o 'local' (valor: ${INSTALL_MODE})"
success "Modo: ${INSTALL_MODE}$([ "$INSTALL_MODE" = docker ] && echo ' (Docker)' || echo ' (sin Docker)')"
if [ -n "$DETECTED_MODE" ] && [ -z "${IAGENTSHUB_MODE:-}" ]; then
  info "Modo de la instalación existente detectado automáticamente."
fi

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

  # container_name es global en cada daemon Docker. Derivar un nombre estable
  # del directorio evita colisiones entre desarrollo, producción y otras
  # instalaciones sin tocar contenedores ajenos.
  WATCHTOWER_NAME=""
  if [ -f .env ]; then
    WATCHTOWER_NAME="$(sed -n 's/^WATCHTOWER_CONTAINER_NAME=//p' .env | tail -1)"
  fi
  if [ -z "$WATCHTOWER_NAME" ] || [ "$WATCHTOWER_NAME" = "watchtower" ]; then
    WATCHTOWER_SUFFIX="$(printf '%s' "$INSTALL_DIR" | cksum | awk '{print $1}')"
    WATCHTOWER_NAME="iagentshub-watchtower-${WATCHTOWER_SUFFIX}"
  fi

  if $FIRST_INSTALL; then
    info "Primera instalación en ${INSTALL_DIR}"
  else
    info "Actualización detectada en ${INSTALL_DIR}"
  fi

  info "Sincronizando docker-compose.yml desde GitHub..."
  curl -fsSL "${COMPOSE_URL}" -o docker-compose.yml
  success "docker-compose.yml actualizado."

  if $FIRST_INSTALL; then
    step "Configurando variables de entorno"
    echo

    INPUT_URL=""; INPUT_USERNAME=""; INPUT_EMAIL=""; INPUT_PORT=""; INPUT_API_URL=""
    case "$INSTALL_COMPONENT" in
      full)
        _prompt "  Dominio público [http://localhost:8007]: " INPUT_URL
        _prompt "  Puerto del frontend [8007]: " INPUT_PORT
        ;;
      backend)
        _prompt "  URL del frontend autorizado [http://localhost:8007]: " INPUT_URL
        _prompt "  Puerto público del backend [8765]: " INPUT_PORT
        ;;
      frontend)
        _prompt "  URL pública del backend (ej: https://api.midominio.com): " INPUT_API_URL
        _prompt "  Puerto del frontend [8007]: " INPUT_PORT
        ;;
    esac
    if [ "$INSTALL_COMPONENT" != "frontend" ]; then
      _prompt "  Usuario público del administrador [admin]: " INPUT_USERNAME
      _prompt "  Email del administrador [admin@localhost.com]: " INPUT_EMAIL
    fi
    PORT="${INPUT_PORT:-$([ "$INSTALL_COMPONENT" = backend ] && echo 8765 || echo 8007)}"
    FRONTEND_URL="${INPUT_URL:-http://localhost:8007}"
    API_BASE_VALUE="${IAGENTSHUB_API_URL:-${INPUT_API_URL:-}}"
    if [ "$INSTALL_COMPONENT" = "frontend" ] && [ -z "$API_BASE_VALUE" ]; then
      error "El frontend aislado requiere IAGENTSHUB_API_URL o indicar la URL del backend."
    fi
    ADMIN_USERNAME="${INPUT_USERNAME:-admin}"
    ADMIN_EMAIL="${INPUT_EMAIL:-admin@localhost.com}"

    AGENTS_SECRET=$(_rand_hex)
    DB_PASSWORD=$(_rand_hex)

    cat > .env <<EOF
# iAgents Hub — configuración generada el $(date '+%Y-%m-%d')
# Para cambiar la configuración edita este fichero y ejecuta:
#   cd ${INSTALL_DIR} && docker compose up -d

IAGENTSHUB_COMPONENT=${INSTALL_COMPONENT}
PORT=$([ "$INSTALL_COMPONENT" = backend ] && echo 8007 || echo "$PORT")
BACKEND_PORT=$([ "$INSTALL_COMPONENT" = backend ] && echo "$PORT" || echo 8765)
GAIA_PORT=8765
GAIA_FRONTEND_URL=${FRONTEND_URL}
GAIA_CORS_ORIGINS=${FRONTEND_URL}
API_BASE=${API_BASE_VALUE}

# Secreto JWT — generado automáticamente, no lo cambies salvo que reinicies desde cero
GAIA_AGENTS_SECRET=${AGENTS_SECRET}

GAIA_ADMIN_USERNAME=${ADMIN_USERNAME}
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

# ── Imagen publicada desde GitHub Actions ─────────────────────────────────────
IMAGE_REPOSITORY=${IMAGE_REPOSITORY}
# Imagen React estable
IMAGE_TAG=latest

# ── Actualización automática ───────────────────────────────────────────────────
# Segundos entre comprobaciones de Watchtower (default 3600 = 1h). 0 la desactiva
# (ejecuta luego: docker compose stop watchtower).
WATCHTOWER_INTERVAL=3600
WATCHTOWER_CONTAINER_NAME=${WATCHTOWER_NAME}

GAIA_TRUSTED_PROXIES=127.0.0.1
EOF

    success ".env creado."
  else
    warn ".env existente conservado. Edita ${INSTALL_DIR}/.env para cambiar la configuración."
    API_BASE_VALUE="${IAGENTSHUB_API_URL:-$(sed -n 's/^API_BASE=//p' .env | tail -1)}"
    if [ "$INSTALL_COMPONENT" = "frontend" ] && [ -z "$API_BASE_VALUE" ]; then
      INPUT_API_URL=""
      _prompt "  URL pública del backend (ej: https://api.midominio.com): " INPUT_API_URL
      API_BASE_VALUE="$INPUT_API_URL"
      [ -n "$API_BASE_VALUE" ] || error "El frontend aislado requiere la URL del backend."
    fi
    awk -v image_repository="$IMAGE_REPOSITORY" \
        -v component="$INSTALL_COMPONENT" -v api_base="$API_BASE_VALUE" \
        -v watchtower_name="$WATCHTOWER_NAME" '
      BEGIN { repo=0; tag=0; component_seen=0; api_seen=0; watchtower_seen=0 }
      /^DOCKER_HUB_USER=/ { next }
      /^IMAGE_REPOSITORY=/ { print "IMAGE_REPOSITORY=" image_repository; repo=1; next }
      /^IMAGE_TAG=/ { print; tag=1; next }
      /^IAGENTSHUB_COMPONENT=/ { print "IAGENTSHUB_COMPONENT=" component; component_seen=1; next }
      /^API_BASE=/ { print "API_BASE=" api_base; api_seen=1; next }
      /^WATCHTOWER_CONTAINER_NAME=/ { print "WATCHTOWER_CONTAINER_NAME=" watchtower_name; watchtower_seen=1; next }
      { print }
      END {
        if (!repo) print "IMAGE_REPOSITORY=" image_repository
        if (!tag) print "IMAGE_TAG=latest"
        if (!component_seen) print "IAGENTSHUB_COMPONENT=" component
        if (!api_seen) print "API_BASE=" api_base
        if (!watchtower_seen) print "WATCHTOWER_CONTAINER_NAME=" watchtower_name
      }
    ' .env > .env.tmp
    mv .env.tmp .env
    info "Imagen GHCR estable configurada."
  fi

  echo
  if $FIRST_INSTALL; then
    info "Descargando imagen desde GitHub Container Registry..."
  else
    info "Descargando imagen actualizada desde GitHub Container Registry..."
  fi

  docker compose -f "${COMPOSE_FILE}" pull \
    || error "No se pudo descargar ${IMAGE_REPOSITORY}. Comprueba que el paquete GHCR sea público."
  # Solo se toca la instalación activa después de descargar correctamente. Así
  # un fallo del registro no provoca una caída del servicio existente.
  docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans --wait --wait-timeout 180 \
    || error "Los contenedores no alcanzaron un estado saludable. Revisa: cd ${INSTALL_DIR} && docker compose logs --tail=200"
  printf 'docker\n' > "$MODE_FILE"
  printf '%s\n' "$INSTALL_COMPONENT" > "$COMPONENT_FILE"

  ADMIN_PASS=""
  if [ "$INSTALL_COMPONENT" != "frontend" ]; then
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
  fi

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
  echo -e "${BOLD}║${RESET}  Componentes › ${CYAN}${INSTALL_COMPONENT}${RESET}"
  if [ "$INSTALL_COMPONENT" != "backend" ]; then
    if [ "$INSTALL_COMPONENT" = "full" ]; then
      echo -e "${BOLD}║${RESET}  Frontend    › ${CYAN}${GAIA_FRONTEND_URL:-http://localhost:${PORT:-8007}}${RESET}"
    else
      echo -e "${BOLD}║${RESET}  Frontend    › ${CYAN}http://localhost:${PORT:-8007}${RESET}"
    fi
  fi
  if [ "$INSTALL_COMPONENT" != "frontend" ]; then
    if [ "$INSTALL_COMPONENT" = "backend" ]; then
      echo -e "${BOLD}║${RESET}  Backend     › ${CYAN}http://localhost:${BACKEND_PORT:-8765}${RESET}"
    fi
    echo -e "${BOLD}║${RESET}  Usuario     › ${CYAN}${GAIA_ADMIN_USERNAME:-admin}${RESET}"
    echo -e "${BOLD}║${RESET}  Email       › ${CYAN}${GAIA_ADMIN_EMAIL:-admin@localhost.com}${RESET}"
    if [ -n "${ADMIN_PASS:-}" ]; then
      echo -e "${BOLD}║${RESET}  Contraseña  › ${GREEN}${ADMIN_PASS}${RESET}"
    else
      echo -e "${BOLD}║${RESET}  Contraseña  › ${YELLOW}ver: docker logs iagentshub-iagentshub-1 | grep -i pass${RESET}"
    fi
  else
    echo -e "${BOLD}║${RESET}  Backend API › ${CYAN}${API_BASE}${RESET}"
  fi
  echo -e "${BOLD}║${RESET}  Directorio  › ${INSTALL_DIR}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
  echo
  echo -e "  Logs:        ${CYAN}cd ${INSTALL_DIR} && docker compose logs -f${RESET}"
  echo -e "  Parar:       ${CYAN}cd ${INSTALL_DIR} && docker compose down${RESET}"
  echo -e "  Actualizar:  automático cada hora (Watchtower) · manual: ${CYAN}curl -fsSL ${GITHUB_RAW}/install.sh | bash${RESET}"
  echo -e "  Desactivar auto-actualización: ${CYAN}cd ${INSTALL_DIR} && docker compose stop watchtower${RESET}"
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
  if $IS_LINUX && [ "$INSTALL_COMPONENT" != "frontend" ] \
      && ! "$PYTHON" -c "import venv" 2>/dev/null; then
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

  # ── 4. Node.js (solo si se instala frontend) ─────────────────────────────
  if [ "$INSTALL_COMPONENT" != "backend" ]; then
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
  # iAgents, backend_fastapi y frontend_react deben quedar como hermanos dentro
  # de INSTALL_DIR; gaia.py resuelve esas rutas de forma relativa.
  step "Repositorios"
  mkdir -p "${INSTALL_DIR}"

  _clone_or_update "${REPO_URL}"          "${INSTALL_DIR}/iAgents"                "iagentshub"
  if [ "$INSTALL_COMPONENT" != "frontend" ]; then
    _clone_or_update "${BACKEND_REPO_URL}" "${INSTALL_DIR}/backend_fastapi" "backend"
  fi
  if [ "$INSTALL_COMPONENT" != "backend" ]; then
    _clone_or_update "${FRONTEND_REACT_URL}" "${INSTALL_DIR}/frontend_react" "frontend React"
  fi
  success "Repositorios listos."

  # El entorno virtual/dependencias Python y el build de React los gestiona
  # gaia.py por su cuenta (ensure_venv / ensure_frontend_build) al arrancar
  # en el paso siguiente — no lo dupliques aquí.

  # ── 6. Configurar .env ────────────────────────────────────────────────────
  ENV_FILE="${INSTALL_DIR}/iAgents/.env"
  if $FIRST_INSTALL; then
    step "Configuración inicial"
    echo

    INPUT_USERNAME=""; INPUT_EMAIL=""; INPUT_PORT=""; INPUT_URL=""; INPUT_API_URL=""
    case "$INSTALL_COMPONENT" in
      full)
        _prompt "  Puerto del frontend [8007]: " INPUT_PORT
        ;;
      backend)
        _prompt "  URL del frontend autorizado [http://localhost:8007]: " INPUT_URL
        _prompt "  Puerto del backend [8765]: " INPUT_PORT
        ;;
      frontend)
        _prompt "  URL pública del backend (ej: https://api.midominio.com): " INPUT_API_URL
        _prompt "  Puerto del frontend [8007]: " INPUT_PORT
        ;;
    esac
    if [ "$INSTALL_COMPONENT" != "frontend" ]; then
      _prompt "  Usuario público del administrador [admin]: " INPUT_USERNAME
      _prompt "  Email del administrador [admin@localhost.com]: " INPUT_EMAIL
    fi
    ADMIN_USERNAME="${INPUT_USERNAME:-admin}"
    ADMIN_EMAIL="${INPUT_EMAIL:-admin@localhost.com}"
    PORT="$([ "$INSTALL_COMPONENT" = backend ] && echo 8007 || echo "${INPUT_PORT:-8007}")"
    GAIA_PORT_VALUE="$([ "$INSTALL_COMPONENT" = backend ] && echo "${INPUT_PORT:-8765}" || echo 8765)"
    FRONTEND_URL="${INPUT_URL:-http://localhost:${PORT}}"
    API_BASE_VALUE="${IAGENTSHUB_API_URL:-${INPUT_API_URL:-}}"
    if [ "$INSTALL_COMPONENT" = "frontend" ] && [ -z "$API_BASE_VALUE" ]; then
      error "El frontend aislado requiere IAGENTSHUB_API_URL o indicar la URL del backend."
    fi

    SECRET=$("$PYTHON" -c "import secrets; print(secrets.token_hex(32))")

    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" <<EOF
# iAgents Hub — configuración generada el $(date '+%Y-%m-%d')
# Edita este fichero y ejecuta: python3 gaia.py start --local

IAGENTSHUB_COMPONENT=${INSTALL_COMPONENT}
PORT=${PORT}
GAIA_PORT=${GAIA_PORT_VALUE}
GAIA_FRONTEND_URL=${FRONTEND_URL}
GAIA_CORS_ORIGINS=${FRONTEND_URL}
API_BASE=${API_BASE_VALUE}

# Secreto JWT — generado automáticamente
GAIA_AGENTS_SECRET=${SECRET}

GAIA_ADMIN_USERNAME=${ADMIN_USERNAME}
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
    API_BASE_VALUE="${IAGENTSHUB_API_URL:-$(sed -n 's/^API_BASE=//p' "$ENV_FILE" | tail -1)}"
    if [ "$INSTALL_COMPONENT" = "frontend" ] && [ -z "$API_BASE_VALUE" ]; then
      INPUT_API_URL=""
      _prompt "  URL pública del backend (ej: https://api.midominio.com): " INPUT_API_URL
      API_BASE_VALUE="$INPUT_API_URL"
      [ -n "$API_BASE_VALUE" ] || error "El frontend aislado requiere la URL del backend."
    fi
    awk -v component="$INSTALL_COMPONENT" -v api_base="$API_BASE_VALUE" '
      BEGIN { component_seen=0; api_seen=0 }
      /^IAGENTSHUB_COMPONENT=/ { print "IAGENTSHUB_COMPONENT=" component; component_seen=1; next }
      /^API_BASE=/ { print "API_BASE=" api_base; api_seen=1; next }
      { print }
      END {
        if (!component_seen) print "IAGENTSHUB_COMPONENT=" component
        if (!api_seen) print "API_BASE=" api_base
      }
    ' "$ENV_FILE" > "${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
  fi

  # ── 7. Arrancar ───────────────────────────────────────────────────────────
  step "Arrancando iAgents Hub"
  cd "${INSTALL_DIR}/iAgents"
  if ! $FIRST_INSTALL; then
    "$PYTHON" gaia.py stop --local
  fi
  "$PYTHON" gaia.py start --local
  printf 'local\n' > "$MODE_FILE"
  printf '%s\n' "$INSTALL_COMPONENT" > "$COMPONENT_FILE"

  # ── Resumen ───────────────────────────────────────────────────────────────
  # shellcheck disable=SC1090
  source "${ENV_FILE}" 2>/dev/null || true
  ADMIN_PASS_FILE="${INSTALL_DIR}/iAgents/data/.admin_pass"
  ADMIN_PASS=""
  if [ "$INSTALL_COMPONENT" != "frontend" ]; then
    for _ in $(seq 1 15); do
      if [ -f "$ADMIN_PASS_FILE" ]; then
        ADMIN_PASS=$(cat "$ADMIN_PASS_FILE" 2>/dev/null || true)
        break
      fi
      sleep 2
    done
  fi

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
  echo -e "${BOLD}║${RESET}  Componentes › ${CYAN}${INSTALL_COMPONENT}${RESET}"
  if [ "$INSTALL_COMPONENT" != "backend" ]; then
    echo -e "${BOLD}║${RESET}  Frontend    › ${CYAN}http://localhost:${PORT:-8007}${RESET}"
  fi
  if [ "$INSTALL_COMPONENT" != "frontend" ]; then
    echo -e "${BOLD}║${RESET}  Backend     › ${CYAN}http://localhost:${GAIA_PORT:-8765}${RESET}"
    echo -e "${BOLD}║${RESET}  Usuario     › ${CYAN}${GAIA_ADMIN_USERNAME:-admin}${RESET}"
    echo -e "${BOLD}║${RESET}  Email       › ${CYAN}${GAIA_ADMIN_EMAIL:-admin@localhost.com}${RESET}"
    if [ -n "${ADMIN_PASS}" ]; then
      echo -e "${BOLD}║${RESET}  Contraseña  › ${GREEN}${ADMIN_PASS}${RESET}"
    else
      echo -e "${BOLD}║${RESET}  Contraseña  › ${YELLOW}ver: ${INSTALL_DIR}/iAgents/data/.admin_pass${RESET}"
    fi
  else
    echo -e "${BOLD}║${RESET}  Backend API › ${CYAN}${API_BASE}${RESET}"
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
