#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
INSTALL_HOST_SCRIPT="$ROOT_DIR/scripts/install-host.sh"
BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/bootstrap.sh"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

run_install_host() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf '%s\n' "Docker already available, skipping host installation"
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

  printf '%s\n' "Docker is not installed and sudo is unavailable. Run scripts/install-host.sh as root first." >&2
  exit 1
}

main() {
  require_command sh
  run_install_host
  "$BOOTSTRAP_SCRIPT"
}

main "$@"
