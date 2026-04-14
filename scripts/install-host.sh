#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "Run this script as root." >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "Missing required command: $1" >&2
    exit 1
  fi
}

detect_os() {
  if [ ! -r /etc/os-release ]; then
    printf '%s\n' "Unsupported OS: /etc/os-release not found" >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu|debian)
      return 0
      ;;
    *)
      printf '%s\n' "Unsupported OS: ${ID:-unknown}. This installer supports Ubuntu/Debian." >&2
      exit 1
      ;;
  esac
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf '%s\n' "Docker and docker compose already installed"
    return 0
  fi

  require_command apt-get
  require_command curl
  require_command gpg

  apt-get update
  apt_install ca-certificates curl gnupg lsb-release ufw

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/"$ID"/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  arch=$(dpkg --print-architecture)
  codename=$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
    "$arch" "$ID" "$codename" > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

configure_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    printf '%s\n' "ufw is not installed, skipping firewall configuration"
    return 0
  fi

  if ufw status | grep -q "Status: inactive"; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow OpenSSH
  fi

  VLESS_PORT=${XRAY_VLESS_PORT:-8443}
  SOCKS_PORT=${XRAY_TELEGRAM_SOCKS_PORT:-29418}

  ufw allow "${VLESS_PORT}/tcp"
  ufw allow "${SOCKS_PORT}/tcp"
  ufw allow "${SOCKS_PORT}/udp"
  ufw --force enable
}

main() {
  detect_os
  install_docker
  configure_firewall

  printf '%s\n' "Host bootstrap completed."
}

main "$@"
