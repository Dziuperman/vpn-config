#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.tuic}"
ENV_EXAMPLE_FILE="${ENV_EXAMPLE_FILE:-$ROOT_DIR/.env.tuic.example}"
TEMPLATE_FILE="$ROOT_DIR/server/tuic.config.template.json"
OUTPUT_DIR="$ROOT_DIR/.generated/tuic"
OUTPUT_FILE="$OUTPUT_DIR/config.json"
CERT_FILE="$OUTPUT_DIR/cert.pem"
KEY_FILE="$OUTPUT_DIR/key.pem"
CLIENT_SUMMARY_FILE="$OUTPUT_DIR/connection-summary.txt"
CLIENT_URI_FILE="$OUTPUT_DIR/shadowrocket-tuic.txt"

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
  if [ -n "${TUIC_SERVER_ADDRESS:-}" ]; then
    printf '%s\n' "$TUIC_SERVER_ADDRESS"
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

  printf '%s\n' "<set TUIC_SERVER_ADDRESS>"
}

ensure_certificates() {
  mkdir -p "$OUTPUT_DIR"

  if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    return 0
  fi

  server_address=$(detect_server_address)
  if ! is_ipv4 "$server_address"; then
    printf '%s\n' "Cannot generate TUIC certificate automatically. Set TUIC_SERVER_ADDRESS to the server IPv4 address." >&2
    exit 1
  fi

  rm -f "$CERT_FILE" "$KEY_FILE"
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 825 \
    -subj "/CN=$server_address" \
    -addext "subjectAltName = IP:$server_address" \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" >/dev/null 2>&1
}

render_template() {
  mkdir -p "$OUTPUT_DIR"

  awk \
    -v tuic_log_level="$TUIC_LOG_LEVEL" \
    -v tuic_port="$TUIC_PORT" \
    -v tuic_uuid="$TUIC_UUID" \
    -v tuic_password="$TUIC_PASSWORD" \
    '
      function esc(value,   copy) {
        copy = value
        gsub(/\\/,"\\\\", copy)
        gsub(/&/,"\\&", copy)
        return copy
      }
      {
        gsub(/__TUIC_LOG_LEVEL__/, esc(tuic_log_level))
        gsub(/__TUIC_PORT__/, tuic_port)
        gsub(/__TUIC_UUID__/, esc(tuic_uuid))
        gsub(/__TUIC_PASSWORD__/, esc(tuic_password))
        print
      }
    ' "$TEMPLATE_FILE" > "$OUTPUT_FILE"
}

render_client_artifacts() {
  server_address=$(detect_server_address)
  node_name=${TUIC_SHADOWROCKET_NAME:-tuic-vpn}
  allow_insecure=${TUIC_SHADOWROCKET_ALLOW_INSECURE:-1}
  tuic_uri="tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${server_address}:${TUIC_PORT}?congestion_control=bbr&alpn=h3&udp_relay_mode=native&allow_insecure=${allow_insecure}#${node_name}"

  {
    printf 'Server address: %s\n' "$server_address"
    printf 'TUIC port: %s\n' "$TUIC_PORT"
    printf 'TUIC UUID: %s\n' "$TUIC_UUID"
    printf 'TUIC password: %s\n' "$TUIC_PASSWORD"
    printf 'TUIC ALPN: h3\n'
    printf 'TUIC congestion_control: bbr\n'
    printf 'Shadowrocket allow_insecure: %s\n' "$allow_insecure"
    printf 'Certificate: %s\n' "$CERT_FILE"
    printf 'Private key: %s\n' "$KEY_FILE"
    printf 'Shadowrocket URI: %s\n' "$tuic_uri"
  } > "$CLIENT_SUMMARY_FILE"

  printf '%s\n' "$tuic_uri" > "$CLIENT_URI_FILE"
}

main() {
  if [ ! -f "$ENV_FILE" ] && [ -f "$ENV_EXAMPLE_FILE" ]; then
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
  fi

  require_file "$TEMPLATE_FILE"
  load_env

  require_var TUIC_LOG_LEVEL
  require_var TUIC_UUID
  require_var TUIC_PASSWORD
  require_port TUIC_PORT

  ensure_certificates
  render_template
  render_client_artifacts

  printf '%s\n' "Rendered $OUTPUT_FILE"
  printf '%s\n' "Wrote $CERT_FILE"
  printf '%s\n' "Wrote $KEY_FILE"
  printf '%s\n' "Wrote $CLIENT_SUMMARY_FILE"
  printf '%s\n' "Wrote $CLIENT_URI_FILE"
}

main "$@"
