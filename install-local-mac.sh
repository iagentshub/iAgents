#!/usr/bin/env bash
# install-local-mac.sh — Instala iAgents Hub en macOS SIN Docker
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install-local-mac.sh | bash
#
# Requisitos: macOS 12+. El script instala Homebrew, Python y git si no están presentes.
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
GITHUB_RAW="https://raw.githubusercontent.com/iagentshub/iagentshub/main"
INSTALL_DIR="${IAGENTSHUB_DIR:-$HOME/iagentshub}"
MIN_PYTHON="3.11"

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║    iAgents Hub · Instalación macOS      ║${RESET}"
echo -e "${BOLD}║    Sin Docker · SQLite                   ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo

# ── Detectar si es actualización ─────────────────────────────────────────────
FIRST_INSTALL=true
[ -f "${INSTALL_DIR}/iagentshub/.env" ] && FIRST_INSTALL=false

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
step "Comprobando Homebrew"
if ! command -v brew &>/dev/null; then
  info "Instalando Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Añadir brew al PATH para el resto del script
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  success "Homebrew instalado."
else
  success "Homebrew ya instalado: $(brew --version | head -1)"
fi

# ── 2. Python ≥ 3.11 ──────────────────────────────────────────────────────────
step "Comprobando Python ${MIN_PYTHON}+"
PYTHON=""
# Buscar primero en brew, luego sistema
for candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "$candidate" &>/dev/null; then
    if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
      PYTHON="$candidate"
      break
    fi
  fi
done

if [ -z "$PYTHON" ]; then
  info "Instalando Python 3.11 via Homebrew..."
  brew install python@3.11
  PYTHON="$(brew --prefix)/bin/python3.11"
  success "Python instalado: $($PYTHON --version)"
else
  success "Python encontrado: $($PYTHON --version)"
fi

# ── 3. Git ────────────────────────────────────────────────────────────────────
step "Comprobando git"
if ! command -v git &>/dev/null; then
  info "Instalando git via Homebrew..."
  brew install git
  success "git instalado."
else
  success "git ya instalado: $(git --version)"
fi

# ── 4. Clonar o actualizar repositorio ────────────────────────────────────────
step "Repositorio"
mkdir -p "${INSTALL_DIR}"
if [ -d "${INSTALL_DIR}/.git" ]; then
  info "Actualizando repositorio en ${INSTALL_DIR}..."
  git -C "${INSTALL_DIR}" pull --ff-only
  success "Repositorio actualizado."
elif [ -d "${INSTALL_DIR}/iagentshub" ]; then
  info "Actualizando repositorio en ${INSTALL_DIR}..."
  git -C "${INSTALL_DIR}" pull --ff-only 2>/dev/null || true
else
  info "Clonando repositorio en ${INSTALL_DIR}..."
  git clone "${REPO_URL}" "${INSTALL_DIR}"
  success "Repositorio clonado."
fi

# ── 5. Entorno virtual y dependencias ────────────────────────────────────────
step "Dependencias Python"
VENV_DIR="${INSTALL_DIR}/.venv"
REQ_FILE="${INSTALL_DIR}/backend/requirements.txt"

[ -f "$REQ_FILE" ] || error "No se encontró backend/requirements.txt — ¿el clone fue correcto?"

if [ ! -d "$VENV_DIR" ]; then
  info "Creando entorno virtual en .venv/..."
  "$PYTHON" -m venv "$VENV_DIR"
fi

HASH_FILE="$VENV_DIR/.req_hash"
CUR_HASH=$(md5 -q "$REQ_FILE" 2>/dev/null || shasum "$REQ_FILE" | cut -d' ' -f1)
SAVED_HASH=$(cat "$HASH_FILE" 2>/dev/null || true)

if [ "$CUR_HASH" != "$SAVED_HASH" ]; then
  info "Instalando dependencias (puede tardar 1-2 minutos)..."
  "$VENV_DIR/bin/pip" install -q --upgrade pip
  "$VENV_DIR/bin/pip" install -q -r "$REQ_FILE"
  echo "$CUR_HASH" > "$HASH_FILE"
  success "Dependencias instaladas."
else
  success "Dependencias ya actualizadas."
fi

# ── 6. Configurar .env ────────────────────────────────────────────────────────
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

  SECRET=$("$VENV_DIR/bin/python3" -c "import secrets; print(secrets.token_hex(32))")

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

# ── 7. Arrancar ───────────────────────────────────────────────────────────────
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
echo -e "  Actualizar:  ${CYAN}curl -fsSL ${GITHUB_RAW}/install-local-mac.sh | bash${RESET}"
echo -e "  Arrancar:    ${CYAN}cd ${INSTALL_DIR}/iagentshub && ./gaia.sh start --local${RESET}"
echo
