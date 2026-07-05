#!/usr/bin/env bash
# install.sh — Instalación y actualización de iAgents Hub desde Docker Hub
#
# Primer uso (instala):
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh | bash
#
# Actualización (descarga compose + imágenes nuevas, mantiene .env y datos):
#   curl -fsSL https://raw.githubusercontent.com/iagentshub/iagentshub/main/install.sh | bash
#
# Solo requiere Docker. Sin clonar repositorios.

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

GITHUB_RAW="https://raw.githubusercontent.com/iagentshub/iagentshub/main"
COMPOSE_URL="${GITHUB_RAW}/docker-compose.hub.yml"
INSTALL_DIR="${IAGENTSHUB_DIR:-$HOME/iagentshub}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

echo
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║           iAgents Hub                   ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo

# ── Comprobar dependencias ────────────────────────────────────────────────────
command -v docker &>/dev/null \
  || error "Docker no está instalado. Instálalo en: https://docs.docker.com/get-docker/"
docker info &>/dev/null \
  || error "Docker no está en ejecución o no tienes permisos. Prueba: sudo usermod -aG docker \$USER"
command -v curl &>/dev/null \
  || error "curl no está instalado (apt install curl / yum install curl)."

# ── Directorio de instalación ─────────────────────────────────────────────────
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# ── Detectar si es primera instalación o actualización ───────────────────────
FIRST_INSTALL=true
[ -f .env ] && FIRST_INSTALL=false

if $FIRST_INSTALL; then
  info "Primera instalación en ${INSTALL_DIR}"
else
  info "Actualización detectada en ${INSTALL_DIR}"
fi

# ── Descargar docker-compose.yml desde GitHub (siempre, para recoger cambios) ─
info "Sincronizando docker-compose.yml desde GitHub..."
curl -fsSL "${COMPOSE_URL}" -o docker-compose.yml
success "docker-compose.yml actualizado."

# ── Configurar .env (solo en primera instalación) ─────────────────────────────
if $FIRST_INSTALL; then
  info "Configurando variables de entorno..."
  echo

  # Leer dominio público (solo si stdin es un terminal)
  if [ -t 0 ]; then
    read -rp "  Dominio público (ej: https://miapp.com) [http://localhost:8007]: " INPUT_URL
    read -rp "  Email del administrador [admin@localhost]: " INPUT_EMAIL
    read -rp "  Puerto del frontend [8007]: " INPUT_PORT
  fi
  FRONTEND_URL="${INPUT_URL:-http://localhost:8007}"
  ADMIN_EMAIL="${INPUT_EMAIL:-admin@localhost}"
  PORT="${INPUT_PORT:-8007}"

  # Generar secreto JWT aleatorio
  AGENTS_SECRET=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 64 \
    || python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null \
    || date +%s%N | sha256sum | head -c 64)

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
# PostgreSQL: postgresql://gaia:changeme@postgres:5432/iagentshub
DATABASE_URL=
GAIA_DB_PASSWORD=changeme

# ── Stripe (opcional) ─────────────────────────────────────────────────────────
STRIPE_SECRET_KEY=
STRIPE_PUBLISHABLE_KEY=
STRIPE_WEBHOOK_SECRET=

# ── Docker Hub ────────────────────────────────────────────────────────────────
DOCKER_HUB_USER=iagenthub
IMAGE_TAG=latest

GAIA_TRUSTED_PROXIES=127.0.0.1
EOF

  success ".env creado."
else
  warn ".env existente conservado. Edita ${INSTALL_DIR}/.env para cambiar la configuración."
fi

# ── Arrancar o actualizar ─────────────────────────────────────────────────────
echo
if $FIRST_INSTALL; then
  info "Descargando imágenes de Docker Hub..."
else
  info "Descargando imágenes actualizadas de Docker Hub..."
  docker compose -f "${COMPOSE_FILE}" down
fi

docker compose -f "${COMPOSE_FILE}" pull
docker compose -f "${COMPOSE_FILE}" up -d

# ── Esperar a que el backend escriba .admin_pass ──────────────────────────────
# IMPORTANTE: </dev/null en cada docker exec para evitar que consuma stdin
# cuando el script se ejecuta via "curl | bash".
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

# ── Leer credenciales del admin ───────────────────────────────────────────────
ADMIN_PASS=$(docker compose -f "${COMPOSE_FILE}" exec -T iagentshub \
  sh -c 'cat /data/.admin_pass' </dev/null 2>/dev/null | tr -d '\r\n' || true)

# shellcheck disable=SC1091
source "${INSTALL_DIR}/.env" 2>/dev/null || true

# ── Resumen final ─────────────────────────────────────────────────────────────
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
