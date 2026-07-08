#!/usr/bin/env bash
# install-local-linux.sh — Instala iAgents Hub en Linux SIN Docker
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-linux.sh | bash
#
# Requisitos: una distribución con apt-get, dnf, yum, pacman o zypper.
# El script instala Python 3.11+ y git mediante el gestor de paquetes nativo
# de la distribución si no están presentes (no usa Homebrew).
# Base de datos: SQLite (incluida en Python, sin configuración adicional).
# Para PostgreSQL o producción real usa el instalador Docker: install.sh

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

REPO_URL="https://github.com/iagentshub/iagentshub.git"
BACKEND_REPO_URL="https://github.com/iagentshub/backend.git"
FRONTEND_REPO_URL="https://github.com/iagentshub/frontend.git"
GITHUB_RAW="https://raw.githubusercontent.com/iagentshub/iagentshub/main"
INSTALL_DIR="${IAGENTSHUB_DIR:-$HOME/iagentshub}"
MIN_PYTHON="3.11"

# sudo solo si hace falta (algunos contenedores/CI ya corren como root)
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo &>/dev/null && SUDO="sudo"
fi

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║    iAgents Hub · Instalación Linux      ║${RESET}"
echo -e "${BOLD}║    Sin Docker · SQLite                   ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo

# ── Detectar si es actualización ─────────────────────────────────────────────
FIRST_INSTALL=true
[ -f "${INSTALL_DIR}/iagentshub/.env" ] && FIRST_INSTALL=false

# ── Gestor de paquetes (detección perezosa: solo si hace falta instalar algo) ──
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
    error "No se encontró un gestor de paquetes soportado (apt-get, dnf, yum, pacman, zypper). Instala Python ${MIN_PYTHON}+ y git manualmente y vuelve a ejecutar este script."
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

# ── 1. Python ≥ 3.11 ──────────────────────────────────────────────────────────
step "Comprobando Python ${MIN_PYTHON}+"
PYTHON="$(_find_python || true)"

if [ -z "$PYTHON" ]; then
  info "Python ${MIN_PYTHON}+ no encontrado. Instalando via el gestor de paquetes..."
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
  [ -n "$PYTHON" ] || error "No se pudo instalar Python ${MIN_PYTHON}+ automáticamente. Instálalo manualmente (p.ej. desde https://python.org o los repositorios de tu distro) y vuelve a ejecutar este script."
  success "Python instalado: $($PYTHON --version)"
else
  success "Python encontrado: $($PYTHON --version)"
fi

# Algunas distros (Debian/Ubuntu) separan el módulo venv del paquete base.
if ! "$PYTHON" -c "import venv" 2>/dev/null; then
  info "Instalando soporte de entornos virtuales (venv)..."
  _detect_pkg_manager
  case "$PKG_MANAGER" in
    apt-get) $PKG_INSTALL python3-venv ;;
    *) : ;; # incluido junto con el paquete python3 en el resto de gestores
  esac
fi

# ── 2. Git ────────────────────────────────────────────────────────────────────
step "Comprobando git"
if ! command -v git &>/dev/null; then
  info "Instalando git..."
  _detect_pkg_manager
  $PKG_INSTALL git
  success "git instalado."
else
  success "git ya instalado: $(git --version)"
fi

# ── 3. Clonar o actualizar repositorios ───────────────────────────────────────
# iagentshub/backend/frontend son repos separados que deben quedar como
# hermanos dentro de INSTALL_DIR — gaia.sh (dentro de iagentshub/) resuelve
# ../backend y ../frontend de forma relativa, y espera este layout exacto.
step "Repositorios"
mkdir -p "${INSTALL_DIR}"

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

_clone_or_update "${REPO_URL}"          "${INSTALL_DIR}/iagentshub" "iagentshub"
_clone_or_update "${BACKEND_REPO_URL}"  "${INSTALL_DIR}/backend"    "backend"
_clone_or_update "${FRONTEND_REPO_URL}" "${INSTALL_DIR}/frontend"   "frontend"
success "Repositorios listos."

# El entorno virtual y las dependencias de Python los gestiona gaia.sh por su
# cuenta (ensure_venv, en ${INSTALL_DIR}/iagentshub/.venv) al arrancar en el
# paso 5 — no lo dupliques aquí.

# ── 4. Configurar .env ────────────────────────────────────────────────────────
ENV_FILE="${INSTALL_DIR}/iagentshub/.env"
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
# Edita este fichero y ejecuta: ./gaia.sh start --local

PORT=${PORT}
GAIA_PORT=8765
GAIA_FRONTEND_URL=http://localhost:${PORT}

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
GAIA_DATA_DIR=${INSTALL_DIR}/iagentshub/data

# SQLite (por defecto) — para PostgreSQL: postgresql://user:pass@host:5432/db
DATABASE_URL=
EOF
  success ".env creado."
else
  warn ".env existente conservado (${ENV_FILE})."
fi

# ── 5. Arrancar ───────────────────────────────────────────────────────────────
step "Arrancando iAgents Hub"
cd "${INSTALL_DIR}/iagentshub"
bash gaia.sh start --local

# ── Resumen ───────────────────────────────────────────────────────────────────
source "${ENV_FILE}" 2>/dev/null || true
ADMIN_PASS_FILE="${INSTALL_DIR}/iagentshub/data/.admin_pass"
ADMIN_PASS=""
# Esperar brevemente a que el backend genere .admin_pass
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
echo -e "${BOLD}║${RESET}  Admin       › ${CYAN}${GAIA_ADMIN_EMAIL:-admin@localhost}${RESET}"
if [ -n "${ADMIN_PASS}" ]; then
  echo -e "${BOLD}║${RESET}  Contraseña  › ${GREEN}${ADMIN_PASS}${RESET}"
else
  echo -e "${BOLD}║${RESET}  Contraseña  › ${YELLOW}ver: ${INSTALL_DIR}/iagentshub/data/.admin_pass${RESET}"
fi
echo -e "${BOLD}║${RESET}  Directorio  › ${INSTALL_DIR}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo
echo -e "  Parar:       ${CYAN}cd ${INSTALL_DIR}/iagentshub && ./gaia.sh stop --local${RESET}"
echo -e "  Logs:        ${CYAN}cd ${INSTALL_DIR}/iagentshub && ./gaia.sh logs --local${RESET}"
echo -e "  Actualizar:  ${CYAN}curl -fsSL ${GITHUB_RAW}/install-local-linux.sh | bash${RESET}"
echo -e "  Arrancar:    ${CYAN}cd ${INSTALL_DIR}/iagentshub && ./gaia.sh start --local${RESET}"
echo
