#!/usr/bin/env bash
# install.sh — Instalación de iAgents Hub desde Docker Hub
#
# Uso en un servidor con Docker instalado:
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh | bash
#
# No requiere clonar ningún repositorio. Solo Docker.

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

COMPOSE_URL="https://raw.githubusercontent.com/iagentshub/iagentshub/main/docker-compose.hub.yml"
INSTALL_DIR="${IAGENTSHUB_DIR:-$HOME/iagentshub}"

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║        iAgents Hub — Instalación        ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo

# ── Comprobar Docker ──────────────────────────────────────────────────────────
command -v docker &>/dev/null   || error "Docker no está instalado. Instálalo en: https://docs.docker.com/get-docker/"
docker info &>/dev/null          || error "Docker no está en ejecución o no tienes permisos. Prueba: sudo usermod -aG docker \$USER"
command -v curl &>/dev/null      || error "curl no está instalado (apt install curl / yum install curl)."

# ── Directorio de instalación ─────────────────────────────────────────────────
info "Directorio de instalación: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# ── Descargar docker-compose.hub.yml ─────────────────────────────────────────
info "Descargando docker-compose.yml desde GitHub..."
curl -fsSL "${COMPOSE_URL}" -o docker-compose.yml
success "docker-compose.yml descargado."

# ── Crear .env si no existe ───────────────────────────────────────────────────
if [ -f .env ]; then
  warn ".env ya existe — se mantiene sin cambios. Borra ${INSTALL_DIR}/.env para reconfigurar."
else
  info "Configurando variables de entorno..."
  echo

  # Leer dominio
  read -rp "  Dominio público (ej: https://miapp.com) [http://localhost:8007]: " INPUT_URL
  FRONTEND_URL="${INPUT_URL:-http://localhost:8007}"

  # Leer email de admin
  read -rp "  Email del administrador [admin@localhost]: " INPUT_EMAIL
  ADMIN_EMAIL="${INPUT_EMAIL:-admin@localhost}"

  # Leer puerto
  read -rp "  Puerto del frontend [8007]: " INPUT_PORT
  PORT="${INPUT_PORT:-8007}"

  # Generar secret JWT aleatorio
  AGENTS_SECRET=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 64 2>/dev/null || \
                  python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || \
                  date +%s%N | sha256sum | head -c 64)

  cat > .env <<EOF
# iAgents Hub — configuración generada por install.sh
# Edita este fichero para cambiar la configuración y luego ejecuta:
#   docker compose up -d

PORT=${PORT}
GAIA_PORT=8765
GAIA_FRONTEND_URL=${FRONTEND_URL}

# Secreto JWT (generado automáticamente — no lo pierdas)
GAIA_AGENTS_SECRET=${AGENTS_SECRET}

GAIA_ADMIN_EMAIL=${ADMIN_EMAIL}
GAIA_REGISTRATION=invite
GAIA_EMAIL_VERIFY=false

# SMTP (desactivado — los emails de reset aparecen en logs del backend)
GAIA_SMTP_HOST=
GAIA_SMTP_PORT=587
GAIA_SMTP_TLS=starttls
GAIA_SMTP_USER=
GAIA_SMTP_PASS=
GAIA_SMTP_FROM=
GAIA_WEBMAIL_URL=
GAIA_RESET_EXPIRE_HOURS=1

GAIA_MAX_GUEST_SESSIONS=200

# Base de datos: vacío = SQLite (suficiente para empezar)
DATABASE_URL=
GAIA_DB_PASSWORD=changeme

# Stripe (desactivado)
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=

# Docker Hub
DOCKER_HUB_USER=iagenthub
IMAGE_TAG=latest

# Proxies de confianza
GAIA_TRUSTED_PROXIES=127.0.0.1
EOF

  success ".env creado."
fi

# ── Arrancar ──────────────────────────────────────────────────────────────────
echo
info "Descargando imágenes de Docker Hub y arrancando..."
docker compose pull
docker compose up -d

# ── Esperar a que el backend esté listo ───────────────────────────────────────
info "Esperando que el backend arranque..."
MAX=30; I=0
until docker compose exec -T backend sh -c "exit 0" &>/dev/null; do
  I=$((I+1))
  [ $I -ge $MAX ] && break
  sleep 2
done

# ── Obtener contraseña del admin ──────────────────────────────────────────────
ADMIN_PASS=$(docker compose exec -T backend sh -c 'cat "$GAIA_DATA_DIR/.admin_pass" 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)
source .env 2>/dev/null || true

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Instalación completada ✓           ║${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  URL         › ${CYAN}${GAIA_FRONTEND_URL:-http://localhost:${PORT:-8007}}${RESET}"
echo -e "${BOLD}║${RESET}  Admin       › ${CYAN}${GAIA_ADMIN_EMAIL:-admin@localhost}${RESET}"
if [ -n "${ADMIN_PASS:-}" ]; then
  echo -e "${BOLD}║${RESET}  Contraseña  › ${GREEN}${ADMIN_PASS}${RESET}"
else
  echo -e "${BOLD}║${RESET}  Contraseña  › (ver logs: docker compose logs backend)"
fi
echo -e "${BOLD}║${RESET}  Directorio  › ${INSTALL_DIR}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo
echo -e "  Logs:        ${CYAN}cd ${INSTALL_DIR} && docker compose logs -f${RESET}"
echo -e "  Parar:       ${CYAN}docker compose down${RESET}"
echo -e "  Actualizar:  ${CYAN}docker compose pull && docker compose up -d${RESET}"
echo
