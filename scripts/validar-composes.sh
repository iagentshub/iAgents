#!/bin/sh
# Valida TODOS los composes, cada uno como se usa de verdad.
#
# El hook anterior ejecutaba `docker compose config` a secas, que solo mira el
# fichero por defecto: los otros cuatro no se comprobaban nunca pese a que el
# `files:` del hook decía docker-compose.*\.yml.
#
# Dos cosas hay que tener en cuenta o esto da falsos positivos:
#
#  - dev.yml es un OVERRIDE, no un compose autónomo. Por su cuenta falla con
#    "data-init has neither an image nor a build context" porque hereda la
#    imagen del base. Se valida apilado sobre docker-compose.yml, que es como
#    lo arranca gaia.py --dev.
#  - frontend.yml y hub.yml usan ${VAR:?mensaje} para exigir configuración.
#    Fallan sin .env A PROPÓSITO, y ese mensaje es la documentación. Se les dan
#    valores de relleno para validar la ESTRUCTURA, que es lo que se está
#    comprobando aquí.
set -eu

fallos=0

comprobar() {
    etiqueta=$1
    shift
    if salida=$(docker compose "$@" config 2>&1 >/dev/null); then
        echo "  ok    $etiqueta"
    else
        echo "  FALLA $etiqueta"
        echo "$salida" | sed 's/^/        /'
        fallos=$((fallos + 1))
    fi
}

comprobar "docker-compose.yml"                 -f docker-compose.yml
comprobar "docker-compose.backend.yml"         -f docker-compose.backend.yml
comprobar "dev.yml (sobre el base)"            -f docker-compose.yml -f docker-compose.dev.yml

# Valores de relleno: solo se valida la estructura, no la configuración real.
API_BASE=http://localhost:8765 \
WATCHTOWER_HTTP_API_TOKEN=relleno \
    comprobar "docker-compose.frontend.yml"    -f docker-compose.frontend.yml
API_BASE=http://localhost:8765 \
WATCHTOWER_HTTP_API_TOKEN=relleno \
    comprobar "docker-compose.hub.yml"         -f docker-compose.hub.yml

[ "$fallos" -eq 0 ] || { echo "composes con errores: $fallos"; exit 1; }
echo "los 5 composes validan"
