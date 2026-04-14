#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RENDER_SCRIPT="$ROOT_DIR/scripts/render-config.sh"
ENV_FILE="$ROOT_DIR/.env"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

main() {
  require_command docker
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi
  "$RENDER_SCRIPT"

  docker compose -f "$ROOT_DIR/compose.yaml" config >/dev/null
  docker run --rm \
    -v "$ROOT_DIR/.generated/server/config.json:/etc/xray/config.json:ro" \
    --entrypoint xray \
    "ghcr.io/xtls/xray-core:${XRAY_IMAGE_TAG:-25.12.8}" \
    run -test -config /etc/xray/config.json >/dev/null

  printf '%s\n' "Compose and Xray config validation succeeded."
}

main "$@"
