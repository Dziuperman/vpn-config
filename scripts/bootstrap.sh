#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE_FILE="$ROOT_DIR/.env.example"
RENDER_SCRIPT="$ROOT_DIR/scripts/render-config.sh"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

create_env_if_missing() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    printf '%s\n' "Created $ENV_FILE from template"
  fi
}

load_env() {
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

upsert_env() {
  key=$1
  value=$2

  if grep -Eq "^${key}=" "$ENV_FILE"; then
    awk -v key="$key" -v value="$value" '
      BEGIN { updated = 0 }
      $0 ~ ("^" key "=") {
        print key "=" value
        updated = 1
        next
      }
      { print }
      END {
        if (!updated) {
          print key "=" value
        }
      }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

random_alnum() {
  length=$1
  openssl rand -hex 32 | awk -v length="$length" 'NR == 1 { print substr($0, 1, length) }'
}

generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
    return 0
  fi

  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi

  openssl rand -hex 16 | awk '{printf "%s-%s-%s-%s-%s\n", substr($0,1,8), substr($0,9,4), substr($0,13,4), substr($0,17,4), substr($0,21,12)}'
}

generate_reality_keys() {
  image="ghcr.io/xtls/xray-core:${XRAY_IMAGE_TAG:-25.12.8}"
  docker pull "$image" >/dev/null
  docker run --rm --entrypoint xray "$image" x25519
}

ensure_env_value() {
  key=$1
  current_value=$2
  generator=$3

  if [ -n "$current_value" ]; then
    return 0
  fi

  generated_value=$($generator)
  upsert_env "$key" "$generated_value"
  printf '%s\n' "Generated $key"
}

ensure_defaults() {
  load_env

  ensure_env_value XRAY_CLIENT_UUID "${XRAY_CLIENT_UUID:-}" generate_uuid
  ensure_env_value XRAY_REALITY_SHORT_ID "${XRAY_REALITY_SHORT_ID:-}" "openssl rand -hex 8"
  ensure_env_value XRAY_TELEGRAM_SOCKS_USER "${XRAY_TELEGRAM_SOCKS_USER:-}" "random_alnum 12"
  ensure_env_value XRAY_TELEGRAM_SOCKS_PASS "${XRAY_TELEGRAM_SOCKS_PASS:-}" "random_alnum 24"

  load_env
  if [ -z "${XRAY_REALITY_PRIVATE_KEY:-}" ]; then
    keys_output=$(generate_reality_keys)
    private_key=$(printf '%s\n' "$keys_output" | awk -F': ' '/^PrivateKey:/ {print $2}')
    public_key=$(printf '%s\n' "$keys_output" | awk -F': ' '/^Password:/ {print $2}')
    upsert_env XRAY_REALITY_PRIVATE_KEY "$private_key"
    printf '%s\n' "Generated XRAY_REALITY_PRIVATE_KEY"
    printf '%s\n' "Derived REALITY public key: $public_key"
  fi
}

main() {
  require_command docker
  require_command openssl
  require_command awk

  if ! docker compose version >/dev/null 2>&1; then
    printf '%s\n' "docker compose is required" >&2
    exit 1
  fi

  if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
    printf '%s\n' "Missing $ENV_EXAMPLE_FILE" >&2
    exit 1
  fi

  create_env_if_missing
  ensure_defaults
  "$RENDER_SCRIPT"

  docker compose -f "$ROOT_DIR/compose.yaml" config >/dev/null
  docker compose -f "$ROOT_DIR/compose.yaml" up -d

  printf '\n%s\n' "VPN is running."
  printf '%s\n' "Server config: $ROOT_DIR/.generated/server/config.json"
  printf '%s\n' "Client summary: $ROOT_DIR/.generated/client/connection-summary.txt"
  printf '%s\n' "Logs: docker compose -f $ROOT_DIR/compose.yaml logs -f"
}

main "$@"
