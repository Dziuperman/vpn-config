#!/bin/sh

set -eu

if [ -z "${ROOT_DIR:-}" ]; then
  ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fi
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
ENV_EXAMPLE_FILE="${ENV_EXAMPLE_FILE:-$ROOT_DIR/.env.example}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/compose.yaml}"
GENERATED_CONFIG_FILE="${GENERATED_CONFIG_FILE:-$ROOT_DIR/.generated/server/config.json}"

log_step() {
  printf '\n[%s] %s\n' "$1" "$2"
}

log_info() {
  printf '%s\n' "$1"
}

log_warn() {
  printf 'Warning: %s\n' "$1" >&2
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
  fi
}

load_env_if_present() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi
}

load_env_required() {
  if [ ! -f "$ENV_FILE" ]; then
    fail "Missing $ENV_FILE"
  fi
  load_env_if_present
}

current_xray_image() {
  load_env_if_present
  printf '%s\n' "ghcr.io/xtls/xray-core:${XRAY_IMAGE_TAG:-25.12.8}"
}

container_name() {
  load_env_if_present
  printf '%s\n' "${XRAY_CONTAINER_NAME:-xray-vpn}"
}

require_port_value() {
  value=$1
  name=$2

  case "$value" in
    ''|*[!0-9]*)
      fail "Invalid port in $name: $value"
      ;;
  esac

  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    fail "Port out of range in $name: $value"
  fi
}

env_port_value() {
  load_env_if_present
  eval "value=\${$1:-$2}"
  require_port_value "$value" "$1"
  printf '%s\n' "$value"
}

port_in_use() {
  port=$1

  if command -v ss >/dev/null 2>&1; then
    ss -lntu "( sport = :$port )" 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit(found ? 0 : 1) }'
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    lsof -nP -iUDP:"$port" >/dev/null 2>&1 && return 0
    return 1
  fi

  return 1
}

docker_registry_reachable() {
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  curl -fsSI --connect-timeout 5 --max-time 10 https://ghcr.io/v2/ >/dev/null 2>&1
}

check_generated_files() {
  [ -f "$GENERATED_CONFIG_FILE" ] || fail "Missing generated config: $GENERATED_CONFIG_FILE"
  [ -f "$ROOT_DIR/.generated/client/connection-summary.txt" ] || fail "Missing client summary"
  [ -f "$ROOT_DIR/.generated/client/shadowrocket-rules.conf" ] || fail "Missing Shadowrocket rules config"
  [ -f "$ROOT_DIR/.generated/client/shadowrocket-vless.txt" ] || fail "Missing Shadowrocket VLESS URI"
}

docker_compose_config_check() {
  docker compose -f "$COMPOSE_FILE" config >/dev/null
}

container_health_status() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(container_name)" 2>/dev/null || true
}

print_runtime_diagnostics() {
  log_info "Container: $(container_name)"
  docker compose -f "$COMPOSE_FILE" ps || true
  docker compose -f "$COMPOSE_FILE" logs --no-color --tail 50 || true
}

require_supported_os() {
  if [ ! -r /etc/os-release ]; then
    fail "Unsupported OS: /etc/os-release not found"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu|debian)
      return 0
      ;;
    *)
      fail "Unsupported OS: ${ID:-unknown}. This installer supports Ubuntu/Debian."
      ;;
  esac
}

host_os_supported() {
  if [ ! -r /etc/os-release ]; then
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu|debian)
      return 0
      ;;
  esac

  return 1
}
