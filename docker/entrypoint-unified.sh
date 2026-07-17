#!/bin/sh
set -e

# ── Directorio de datos ───────────────────────────────────────────────────────
DATA_DIR="${GAIA_DATA_DIR:-/data}"
mkdir -p "${DATA_DIR}/logs"

# Crear settings.json con secret JWT aleatorio y valores de plataforma por defecto
# si no existe. Los valores se pueden cambiar después desde /admin/ → Configuración.
if [ ! -f "${DATA_DIR}/settings.json" ]; then
  SECRET=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64 2>/dev/null || \
           python3 -c "import secrets; print(secrets.token_hex(32))")
  # Valores de plataforma por defecto (conservadores para auto-hospedaje):
  #   billing_enabled      → false  (planes de pago desactivados)
  #   registration         → closed (solo el admin puede crear cuentas)
  #   guest_enabled        → false  (sin acceso como invitado)
  #   max_users            → 0      (sin límite)
  #   max_concurrent_sessions → 0   (sin límite)
  #   email_verify         → false
  #   log_retention_days   → 30
  printf '{
  "jwt_secret": "%s",
  "billing_enabled": false,
  "registration": "closed",
  "guest_enabled": false,
  "max_users": 0,
  "max_concurrent_sessions": 0,
  "email_verify": false,
  "log_retention_days": 30
}\n' "$SECRET" > "${DATA_DIR}/settings.json"
  echo "[iagentshub] settings.json creado con valores por defecto."
fi

# ── Inyectar variables en config.js (Stripe, API_BASE) ───────────────────────
: "${API_BASE:=}"
: "${STRIPE_PUBLISHABLE_KEY:=}"
TEMPLATE="/usr/share/nginx/html/env.template.js"
CONFIG="/usr/share/nginx/html/env.js"
if [ -f "$TEMPLATE" ]; then
  envsubst '${API_BASE} ${STRIPE_PUBLISHABLE_KEY}' < "$TEMPLATE" > "$CONFIG"
fi

# ── Arrancar nginx + uvicorn vía supervisor ───────────────────────────────────
echo "[iagentshub] Arrancando servicios..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
