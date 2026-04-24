#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.tuic}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/compose.tuic.yaml}"
RENDER_SCRIPT="$ROOT_DIR/scripts/render-tuic-config.sh"

main() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi

  "$RENDER_SCRIPT"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config >/dev/null
  docker run --rm \
    -v "$ROOT_DIR/.generated/tuic/config.json:/etc/sing-box/config.json:ro" \
    -v "$ROOT_DIR/.generated/tuic/cert.pem:/etc/sing-box/certs/cert.pem:ro" \
    -v "$ROOT_DIR/.generated/tuic/key.pem:/etc/sing-box/certs/key.pem:ro" \
    --entrypoint sing-box \
    "ghcr.io/sagernet/sing-box:${SINGBOX_IMAGE_TAG:-v1.13.8}" \
    check -c /etc/sing-box/config.json >/dev/null

  printf '%s\n' "Compose and TUIC config validation succeeded."
  if [ -f "$ROOT_DIR/.generated/tuic/shadowrocket-tuic.txt" ]; then
    printf '%s' "Shadowrocket URI: "
    cat "$ROOT_DIR/.generated/tuic/shadowrocket-tuic.txt"
  fi
}

main "$@"
