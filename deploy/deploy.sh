#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"

base_file="docker-compose.yml"
override_file="compose.production.override.yml"
previous_file=".previous-image-tag"

start_release() {
  target_tag="$1"
  IMAGE_TAG="$target_tag" docker compose \
    -f "$base_file" -f "$override_file" pull iagentshub postgres
  IMAGE_TAG="$target_tag" docker compose \
    -f "$base_file" -f "$override_file" up \
    --detach --remove-orphans --wait --wait-timeout 180
  docker compose -f "$base_file" -f "$override_file" \
    stop watchtower docker-proxy >/dev/null 2>&1 || true

  expected_version=${target_tag#react-}
  actual_version=$(curl -fsS http://10.20.10.5:8007/api/health \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
  test "$actual_version" = "$expected_version"
}

rollback() {
  test -s "$previous_file" || {
    echo "No hay una release anterior registrada para el rollback." >&2
    exit 1
  }
  rollback_tag=$(tr -d '\r\n' < "$previous_file")
  echo "Restaurando $rollback_tag"
  start_release "$rollback_tag"
}

if [ "${1:-}" = "--rollback" ]; then
  rollback
  exit 0
fi

new_tag="${1:-}"
case "$new_tag" in
  react-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *)
    echo "Etiqueta de imagen no válida: $new_tag" >&2
    exit 2
    ;;
esac

current_tag=$(sed -n 's/^IMAGE_TAG=//p' .env | tail -n 1)
if [ "$current_tag" = "$new_tag" ]; then
  echo "$new_tag ya está desplegada."
  exit 0
fi

if [ -n "$current_tag" ] && [ "$current_tag" != "latest" ]; then
  printf '%s\n' "$current_tag" > "$previous_file.tmp"
  mv "$previous_file.tmp" "$previous_file"
fi

echo "Desplegando $new_tag"
if ! start_release "$new_tag"; then
  echo "La nueva release no quedó healthy." >&2
  if [ -s "$previous_file" ]; then
    rollback
  fi
  exit 1
fi

sed "s/^IMAGE_TAG=.*/IMAGE_TAG=$new_tag/" .env > .env.tmp
mv .env.tmp .env
echo "Release $new_tag activa y healthy."
