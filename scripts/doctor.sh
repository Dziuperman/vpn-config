#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"

STRICT=0
if [ "${1:-}" = "--strict" ]; then
  STRICT=1
fi

check_item() {
  name=$1
  shift

  if "$@"; then
    printf '[ok] %s\n' "$name"
    return 0
  fi

  printf '[fail] %s\n' "$name" >&2
  return 1
}

check_docker() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

check_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi

  status=$(ufw status 2>/dev/null || true)
  case "$status" in
    *"Status: inactive"*)
      return 0
      ;;
    *"Status: active"*)
      vless_port=$(env_port_value XRAY_VLESS_PORT 8443)
      socks_port=$(env_port_value XRAY_TELEGRAM_SOCKS_PORT 29418)
      printf '%s\n' "$status" | grep -q "${vless_port}/tcp" || return 1
      printf '%s\n' "$status" | grep -q "${socks_port}/tcp" || return 1
      printf '%s\n' "$status" | grep -q "${socks_port}/udp" || return 1
      return 0
      ;;
  esac

  return 1
}

check_runtime_ports() {
  vless_port=$(env_port_value XRAY_VLESS_PORT 8443)
  socks_port=$(env_port_value XRAY_TELEGRAM_SOCKS_PORT 29418)
  port_in_use "$vless_port" && port_in_use "$socks_port"
}

check_registry_with_warning() {
  if docker_registry_reachable; then
    printf '[ok] %s\n' "ghcr.io reachability"
    return 0
  fi

  printf '[warn] %s\n' "ghcr.io reachability" >&2
  return 0
}

main() {
  log_step "doctor" "Inspecting host and deployment state"
  load_env_if_present

  status=0

  if host_os_supported; then
    printf '[ok] %s\n' "supported OS"
  else
    printf '[ok] %s\n' "supported OS (skipped on non-Ubuntu/Debian host)"
  fi
  check_item "docker and compose" check_docker || status=1
  check_registry_with_warning || true
  check_item "firewall rules" check_firewall || status=1

  if check_docker; then
    check_item "compose config" docker_compose_config_check || status=1
    check_item "generated artifacts" check_generated_files || status=1
    health=$(container_health_status)
    case "$health" in
      healthy|running)
        printf '[ok] container health: %s\n' "$health"
        ;;
      *)
        printf '[fail] container health: %s\n' "${health:-missing}" >&2
        status=1
        ;;
    esac
    check_item "published ports active" check_runtime_ports || status=1
  fi

  if [ "$status" -ne 0 ] && [ "$STRICT" -eq 1 ]; then
    print_runtime_diagnostics >&2 || true
    exit 1
  fi

  if [ "$status" -ne 0 ]; then
    exit 1
  fi

  log_info "Doctor checks passed."
}

main "$@"
