#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RENDER_SCRIPT="$ROOT_DIR/scripts/render-config.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"

wait_for_container_health() {
  container_name=$(container_name)
  attempts=30
  count=1

  while [ "$count" -le "$attempts" ]; do
    status=$(container_health_status)

    case "$status" in
      healthy)
        log_info "Container $container_name is healthy"
        return 0
        ;;
      running)
        log_info "Container $container_name is running"
        return 0
        ;;
      unhealthy|exited|dead)
        log_info "Container $container_name failed with status: $status"
        print_runtime_diagnostics >&2
        exit 1
        ;;
    esac

    sleep 2
    count=$((count + 1))
  done

  log_info "Timed out waiting for container health"
  print_runtime_diagnostics >&2
  exit 1
}

create_env_if_missing() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    log_info "Created $ENV_FILE from template"
  fi
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
  char_count=$1
  openssl rand -hex 32 | cut -c "1-${char_count}"
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
  log_info "Generated $key"
}

ensure_defaults() {
  load_env_required

  ensure_env_value XRAY_CLIENT_UUID "${XRAY_CLIENT_UUID:-}" generate_uuid
  ensure_env_value XRAY_REALITY_SHORT_ID "${XRAY_REALITY_SHORT_ID:-}" "openssl rand -hex 8"
  ensure_env_value XRAY_TELEGRAM_SOCKS_USER "${XRAY_TELEGRAM_SOCKS_USER:-}" "random_alnum 12"
  ensure_env_value XRAY_TELEGRAM_SOCKS_PASS "${XRAY_TELEGRAM_SOCKS_PASS:-}" "random_alnum 24"

  load_env_required
  if [ -z "${XRAY_REALITY_PRIVATE_KEY:-}" ]; then
    keys_output=$(generate_reality_keys)
    private_key=$(printf '%s\n' "$keys_output" | awk -F': ' '/^PrivateKey:/ {print $2}')
    public_key=$(printf '%s\n' "$keys_output" | awk -F': ' '/^Password:/ {print $2}')
    upsert_env XRAY_REALITY_PRIVATE_KEY "$private_key"
    log_info "Generated XRAY_REALITY_PRIVATE_KEY"
    log_info "Derived REALITY public key: $public_key"
  fi
}

check_runtime_ports() {
  load_env_if_present
  vless_port=$(env_port_value XRAY_VLESS_PORT 8443)
  socks_port=$(env_port_value XRAY_TELEGRAM_SOCKS_PORT 29418)

  port_in_use "$vless_port" || fail "Expected VLESS port $vless_port to be open after deployment."
  port_in_use "$socks_port" || fail "Expected SOCKS port $socks_port to be open after deployment."
}

main() {
  log_step "deploy" "Running bootstrap deployment"
  require_command docker
  require_command openssl
  require_command awk

  if ! docker compose version >/dev/null 2>&1; then
    printf '%s\n' "docker compose is required" >&2
    exit 1
  fi

  if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
    fail "Missing $ENV_EXAMPLE_FILE"
  fi

  create_env_if_missing
  ensure_defaults
  "$RENDER_SCRIPT"

  log_info "Validating compose configuration"
  docker_compose_config_check

  log_info "Starting Xray container"
  docker compose -f "$COMPOSE_FILE" up -d
  wait_for_container_health
  check_runtime_ports

  printf '\n%s\n' "VPN is running."
  log_info "Server config: $ROOT_DIR/.generated/server/config.json"
  log_info "Client summary: $ROOT_DIR/.generated/client/connection-summary.txt"
  log_info "Shadowrocket config: $ROOT_DIR/.generated/client/shadowrocket.conf"
  log_info "Logs: docker compose -f $COMPOSE_FILE logs -f"
}

main "$@"
