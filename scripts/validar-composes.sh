#!/bin/sh
# Compatibilidad para hooks y llamadas antiguas. La implementación vive en
# gaia.py para que la validación prepare .env igual que start/update/reset.
set -eu
exec python3 gaia.py validate
