#!/bin/sh
set -e

# ── Directorio de datos ───────────────────────────────────────────────────────
DATA_DIR="${GAIA_DATA_DIR:-/data}"
mkdir -p "${DATA_DIR}/logs"

# Crear settings.json con secret JWT aleatorio y valores de plataforma por defecto
# si no existe. Los valores se pueden cambiar después desde /admin/ → Configuración.
if [ ! -f "${DATA_DIR}/settings.json" ]; then
  SECRET=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 64 2>/dev/null || \
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
  # Las comillas simples son intencionadas: envsubst recibe los NOMBRES de las
  # variables que debe sustituir, no sus valores.
  # shellcheck disable=SC2016
  envsubst '${API_BASE} ${STRIPE_PUBLISHABLE_KEY}' < "$TEMPLATE" > "$CONFIG"
fi

# ── Bajar privilegios ─────────────────────────────────────────────────────────
# Todo lo de arriba se hace como root a propósito, porque en una instalación ya
# existente el volumen /data pertenece a root: un `USER gaia` en el Dockerfile
# dejaría al proceso sin poder escribir su propia base de datos justo al
# ACTUALIZAR, que es cuando ya hay datos dentro.
USUARIO="${GAIA_USER:-gaia}"
if [ "$(id -u)" = "0" ]; then
  # El chown -R solo la primera vez: recorrer un /data grande en cada arranque
  # cuesta segundos, y después ya es del usuario correcto porque lo que escribe
  # el proceso nace con su dueño.
  if [ "$(stat -c %U "$DATA_DIR")" != "$USUARIO" ]; then
    echo "[iagentshub] ${DATA_DIR} era de $(stat -c %U "$DATA_DIR"); cediéndolo a ${USUARIO}..."
    chown -R "$USUARIO:$USUARIO" "$DATA_DIR"
  fi
  chown "$USUARIO:$USUARIO" "$CONFIG" 2>/dev/null || true
fi

# supervisord se queda como root a propósito, y baja los privilegios de sus
# hijos con `user=` (ver supervisord.conf). Bajarlos aquí con setpriv, que era
# lo primero que se intentó, NO funciona: al cambiar de uid el kernel marca el
# proceso como no volcable y /proc/self/fd/1 pasa a pertenecer a root, así que
# supervisord ya no puede abrir /dev/stdout para redirigir la salida de nginx
# ni de uvicorn — arranca y ambos mueren en bucle con EACCES.
#
# Lo que importa es quién sirve red y quién toca los datos: nginx y uvicorn son
# gaia. supervisord no escucha en ningún sitio, solo lanza y vigila.
echo "[iagentshub] Arrancando servicios..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
