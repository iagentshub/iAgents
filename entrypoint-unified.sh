#!/bin/sh
set -e

# ── Directorio de datos ───────────────────────────────────────────────────────
DATA_DIR="${GAIA_DATA_DIR:-/data}"
mkdir -p "${DATA_DIR}/logs"

# Crear settings.json con secret JWT aleatorio si no existe
if [ ! -f "${DATA_DIR}/settings.json" ]; then
  SECRET=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64 2>/dev/null || \
           python3 -c "import secrets; print(secrets.token_hex(32))")
  printf '{"jwt_secret":"%s"}\n' "$SECRET" > "${DATA_DIR}/settings.json"
  echo "[iagentshub] settings.json creado con secret aleatorio."
fi

# ── Inyectar variables en config.js (Stripe, API_BASE) ───────────────────────
: "${API_BASE:=}"
: "${STRIPE_PUBLISHABLE_KEY:=}"
TEMPLATE="/usr/share/nginx/html/assets/js/config.template.js"
CONFIG="/usr/share/nginx/html/assets/js/config.js"
if [ -f "$TEMPLATE" ]; then
  envsubst '${API_BASE} ${STRIPE_PUBLISHABLE_KEY}' < "$TEMPLATE" > "$CONFIG"
fi

# ── Arrancar nginx + uvicorn vía supervisor ───────────────────────────────────
echo "[iagentshub] Arrancando servicios..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
