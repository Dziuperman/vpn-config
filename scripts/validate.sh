#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RENDER_SCRIPT="$ROOT_DIR/scripts/render-config.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"

main() {
  log_step "validate" "Checking compose and Xray config"
  require_command docker
  load_env_if_present
  "$RENDER_SCRIPT"

  docker_compose_config_check
  docker run --rm \
    -v "$ROOT_DIR/.generated/server/config.json:/etc/xray/config.json:ro" \
    --entrypoint xray \
    "$(current_xray_image)" \
    run -test -config /etc/xray/config.json >/dev/null

  log_info "Compose and Xray config validation succeeded."
}

main "$@"
