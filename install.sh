#!/bin/sh

set -eu

printf '%s\n' "Warning: install.sh is a legacy local convenience entrypoint. Prefer ansible/playbooks/provision.yml and ansible/playbooks/deploy.yml for managed deployments." >&2

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"

INSTALL_HOST_SCRIPT="$ROOT_DIR/scripts/install-host.sh"
BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/bootstrap.sh"
DOCTOR_SCRIPT="$ROOT_DIR/scripts/doctor.sh"

run_install_host() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log_info "Docker already available, skipping host installation"
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    "$INSTALL_HOST_SCRIPT"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$INSTALL_HOST_SCRIPT"
    return 0
  fi

  fail "Docker is not installed and sudo is unavailable. Run scripts/install-host.sh as root first."
}

preflight() {
  log_step "preflight" "Checking local prerequisites and deployment inputs"

  require_command sh
  require_command awk
  require_command openssl

  if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
    fail "Missing $ENV_EXAMPLE_FILE"
  fi

  if command -v curl >/dev/null 2>&1; then
    if docker_registry_reachable; then
      log_info "Docker registry connectivity: ok"
    else
      log_warn "Cannot verify ghcr.io reachability during preflight. Deployment may still succeed if Docker daemon networking is available."
    fi
  else
    log_info "curl not found yet, skipping registry preflight until host bootstrap"
  fi
}

verify() {
  log_step "verify" "Running post-deploy diagnostics"
  "$DOCTOR_SCRIPT" --strict
}

main() {
  preflight

  log_step "host" "Preparing host dependencies"
  run_install_host

  log_step "deploy" "Running bootstrap deployment"
  "$BOOTSTRAP_SCRIPT"

  verify

  log_step "summary" "Deployment completed"
  log_info "Client summary: $ROOT_DIR/.generated/client/connection-summary.txt"
  log_info "Shadowrocket rules: $ROOT_DIR/.generated/client/shadowrocket-rules.conf"
  log_info "Shadowrocket VLESS URI: $ROOT_DIR/.generated/client/shadowrocket-vless.txt"
}

main "$@"
