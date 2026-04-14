#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"

ensure_ssh_rule_hint() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi

  status=$(ufw status 2>/dev/null || true)
  case "$status" in
    *"Status: active"*)
      printf '%s\n' "$status" | grep -Eq 'OpenSSH|22/tcp' || fail "ufw is active but SSH is not obviously allowed. Add an SSH rule before continuing."
      ;;
  esac
}

check_ports() {
  vless_port=$(env_port_value XRAY_VLESS_PORT 8443)
  socks_port=$(env_port_value XRAY_TELEGRAM_SOCKS_PORT 29418)

  if port_in_use "$vless_port"; then
    fail "Port $vless_port is already in use."
  fi

  if [ "$socks_port" != "$vless_port" ] && port_in_use "$socks_port"; then
    fail "Port $socks_port is already in use."
  fi
}

main() {
  log_step "preflight" "Running host and deployment checks"

  require_command sh
  require_command awk
  require_command openssl

  if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
    fail "Missing $ENV_EXAMPLE_FILE"
  fi

  if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    fail "Run as root or install sudo."
  fi

  if host_os_supported; then
    log_info "Host OS check: supported"
  else
    log_info "Host OS check: skipped on non-Ubuntu/Debian environment"
  fi
  load_env_if_present
  check_ports
  if host_os_supported; then
    ensure_ssh_rule_hint
  fi

  if command -v curl >/dev/null 2>&1; then
    if docker_registry_reachable; then
      log_info "Registry connectivity to ghcr.io: ok"
    else
      log_warn "Cannot verify ghcr.io reachability from this host."
    fi
  else
    log_info "curl is not installed yet; registry connectivity check skipped"
  fi

  log_info "Preflight checks passed."
}

main "$@"
