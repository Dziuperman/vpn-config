#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
TEMPLATE_FILE="$ROOT_DIR/server/config.template.json"
OUTPUT_DIR="$ROOT_DIR/.generated/server"
OUTPUT_FILE="$OUTPUT_DIR/config.json"
CLIENT_OUTPUT_DIR="$ROOT_DIR/.generated/client"
CLIENT_OUTPUT_FILE="$CLIENT_OUTPUT_DIR/connection-summary.txt"
SHADOWROCKET_TEMPLATE_FILE="$ROOT_DIR/client/shadowrocket/default.conf"
SHADOWROCKET_OUTPUT_FILE="$CLIENT_OUTPUT_DIR/shadowrocket.conf"
SHADOWROCKET_URI_FILE="$CLIENT_OUTPUT_DIR/shadowrocket-vless.txt"

is_ipv4() {
  value=$1
  printf '%s\n' "$value" | awk '
    BEGIN { ok = 1 }
    NF != 1 { ok = 0 }
    {
      split($1, parts, ".")
      if (length(parts) != 4) {
        ok = 0
      } else {
        for (i = 1; i <= 4; i++) {
          if (parts[i] !~ /^[0-9]+$/ || parts[i] < 0 || parts[i] > 255) {
            ok = 0
          }
        }
      }
    }
    END { exit(ok ? 0 : 1) }
  '
}

require_file() {
  if [ ! -f "$1" ]; then
    printf '%s\n' "Missing required file: $1" >&2
    exit 1
  fi
}

load_env() {
  require_file "$ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

require_var() {
  eval "value=\${$1-}"
  if [ -z "${value}" ]; then
    printf '%s\n' "Missing required env var: $1" >&2
    exit 1
  fi
}

require_port() {
  eval "value=\${$1-}"
  case "$value" in
    ''|*[!0-9]*)
      printf '%s\n' "Invalid port in $1: $value" >&2
      exit 1
      ;;
  esac

  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    printf '%s\n' "Port out of range in $1: $value" >&2
    exit 1
  fi
}

detect_server_address() {
  if [ -n "${XRAY_SERVER_ADDRESS:-}" ]; then
    printf '%s\n' "$XRAY_SERVER_ADDRESS"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    for endpoint in \
      "https://api.ipify.org" \
      "https://ipv4.icanhazip.com" \
      "https://ifconfig.me/ip"
    do
      address=$(curl -4fsS --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null | tr -d '\r\n' || true)
      if [ -n "${address:-}" ] && is_ipv4 "$address"; then
        printf '%s\n' "$address"
        return 0
      fi
    done
  fi

  if command -v hostname >/dev/null 2>&1; then
    address=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "${address:-}" ] && is_ipv4 "$address"; then
      printf '%s\n' "$address"
      return 0
    fi
  fi

  if command -v ip >/dev/null 2>&1; then
    address=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')
    if [ -n "${address:-}" ] && is_ipv4 "$address"; then
      printf '%s\n' "$address"
      return 0
    fi
  fi

  printf '%s\n' "<set XRAY_SERVER_ADDRESS>"
}

build_public_key() {
  image="ghcr.io/xtls/xray-core:${XRAY_IMAGE_TAG:-25.12.8}"
  docker run --rm --entrypoint xray "$image" x25519 -i "$XRAY_REALITY_PRIVATE_KEY" 2>/dev/null \
    | awk -F': ' '/^Password:/ {print $2}'
}

render_template() {
  mkdir -p "$OUTPUT_DIR" "$CLIENT_OUTPUT_DIR"

  awk \
    -v xray_log_level="$XRAY_LOG_LEVEL" \
    -v xray_vless_port="$XRAY_VLESS_PORT" \
    -v xray_client_uuid="$XRAY_CLIENT_UUID" \
    -v xray_reality_dest="$XRAY_REALITY_DEST" \
    -v xray_reality_server_name="$XRAY_REALITY_SERVER_NAME" \
    -v xray_reality_private_key="$XRAY_REALITY_PRIVATE_KEY" \
    -v xray_reality_short_id="$XRAY_REALITY_SHORT_ID" \
    -v xray_telegram_socks_port="$XRAY_TELEGRAM_SOCKS_PORT" \
    -v xray_telegram_socks_user="$XRAY_TELEGRAM_SOCKS_USER" \
    -v xray_telegram_socks_pass="$XRAY_TELEGRAM_SOCKS_PASS" \
    '
      function esc(value,   copy) {
        copy = value
        gsub(/\\/,"\\\\", copy)
        gsub(/&/,"\\&", copy)
        return copy
      }
      {
        gsub(/__XRAY_LOG_LEVEL__/, esc(xray_log_level))
        gsub(/__XRAY_VLESS_PORT__/, xray_vless_port)
        gsub(/__XRAY_CLIENT_UUID__/, esc(xray_client_uuid))
        gsub(/__XRAY_REALITY_DEST__/, esc(xray_reality_dest))
        gsub(/__XRAY_REALITY_SERVER_NAME__/, esc(xray_reality_server_name))
        gsub(/__XRAY_REALITY_PRIVATE_KEY__/, esc(xray_reality_private_key))
        gsub(/__XRAY_REALITY_SHORT_ID__/, esc(xray_reality_short_id))
        gsub(/__XRAY_TELEGRAM_SOCKS_PORT__/, xray_telegram_socks_port)
        gsub(/__XRAY_TELEGRAM_SOCKS_USER__/, esc(xray_telegram_socks_user))
        gsub(/__XRAY_TELEGRAM_SOCKS_PASS__/, esc(xray_telegram_socks_pass))
        print
      }
    ' "$TEMPLATE_FILE" > "$OUTPUT_FILE"
}

render_client_summary() {
  server_address=$(detect_server_address)
  public_key=$(build_public_key || true)
  vless_uri_public_key=${public_key:-<run bootstrap after Docker image pull>}
  vless_uri="vless://${XRAY_CLIENT_UUID}@${server_address}:${XRAY_VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${XRAY_REALITY_SERVER_NAME}&fp=chrome&pbk=${vless_uri_public_key}&sid=${XRAY_REALITY_SHORT_ID}&type=tcp&headerType=none#xray-vpn"

  {
    printf 'Server address: %s\n' "$server_address"
    printf 'VLESS port: %s\n' "$XRAY_VLESS_PORT"
    printf 'VLESS UUID: %s\n' "$XRAY_CLIENT_UUID"
    printf 'REALITY serverName: %s\n' "$XRAY_REALITY_SERVER_NAME"
    printf 'REALITY public key: %s\n' "$vless_uri_public_key"
    printf 'REALITY shortId: %s\n' "$XRAY_REALITY_SHORT_ID"
    printf 'VLESS URI: %s\n' "$vless_uri"
    printf 'Telegram SOCKS: socks5://%s:%s@%s:%s\n' \
      "$XRAY_TELEGRAM_SOCKS_USER" \
      "$XRAY_TELEGRAM_SOCKS_PASS" \
      "$server_address" \
      "$XRAY_TELEGRAM_SOCKS_PORT"
  } > "$CLIENT_OUTPUT_FILE"

  printf '%s\n' "$vless_uri" > "$SHADOWROCKET_URI_FILE"
}

render_shadowrocket_config() {
  require_file "$SHADOWROCKET_TEMPLATE_FILE"

  server_address=$(detect_server_address)
  public_key=$(build_public_key || true)
  vless_uri_public_key=${public_key:-}

  awk \
    -v server_address="$server_address" \
    -v xray_vless_port="$XRAY_VLESS_PORT" \
    -v xray_client_uuid="$XRAY_CLIENT_UUID" \
    -v xray_reality_server_name="$XRAY_REALITY_SERVER_NAME" \
    -v xray_reality_short_id="$XRAY_REALITY_SHORT_ID" \
    -v xray_reality_public_key="$vless_uri_public_key" \
    -v xray_telegram_socks_port="$XRAY_TELEGRAM_SOCKS_PORT" \
    -v xray_telegram_socks_user="$XRAY_TELEGRAM_SOCKS_USER" \
    -v xray_telegram_socks_pass="$XRAY_TELEGRAM_SOCKS_PASS" \
    '
      BEGIN {
        print "# Generated by scripts/render-config.sh"
        print "[Proxy]"
        print "xray-vpn = vless," server_address "," xray_vless_port ",password=" xray_client_uuid ",flow=xtls-rprx-vision,tls=true,fast-open=true,peer=" xray_reality_server_name ",public-key=" xray_reality_public_key ",short-id=" xray_reality_short_id ",client-fingerprint=chrome"
        print "telegram-socks = socks5," server_address "," xray_telegram_socks_port "," xray_telegram_socks_user "," xray_telegram_socks_pass
        print ""
        print "[Proxy Group]"
        print "PROXY = select, xray-vpn, telegram-socks, DIRECT"
        print ""
      }
      { print }
    ' "$SHADOWROCKET_TEMPLATE_FILE" > "$SHADOWROCKET_OUTPUT_FILE"
}

main() {
  require_file "$TEMPLATE_FILE"
  load_env

  require_var XRAY_LOG_LEVEL
  require_var XRAY_CLIENT_UUID
  require_var XRAY_REALITY_DEST
  require_var XRAY_REALITY_SERVER_NAME
  require_var XRAY_REALITY_PRIVATE_KEY
  require_var XRAY_REALITY_SHORT_ID
  require_var XRAY_TELEGRAM_SOCKS_USER
  require_var XRAY_TELEGRAM_SOCKS_PASS

  require_port XRAY_VLESS_PORT
  require_port XRAY_TELEGRAM_SOCKS_PORT

  render_template
  render_client_summary
  render_shadowrocket_config

  printf '%s\n' "Rendered $OUTPUT_FILE"
  printf '%s\n' "Wrote $CLIENT_OUTPUT_FILE"
  printf '%s\n' "Wrote $SHADOWROCKET_OUTPUT_FILE"
  printf '%s\n' "Wrote $SHADOWROCKET_URI_FILE"
}

main "$@"
