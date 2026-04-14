#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

ensure_root() {
  [ "$(id -u)" -eq 0 ] || fail "Run this script as root."
}

docker_compose_available() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

ensure_docker_repo() {
  install -m 0755 -d /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/"$ID"/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  arch=$(dpkg --print-architecture)
  codename=$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")
  repo_line=$(printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable' "$arch" "$ID" "$codename")

  if [ -f /etc/apt/sources.list.d/docker.list ] && grep -Fqx "$repo_line" /etc/apt/sources.list.d/docker.list; then
    return 0
  fi

  printf '%s\n' "$repo_line" > /etc/apt/sources.list.d/docker.list
}

install_docker() {
  if docker_compose_available; then
    log_info "Docker and docker compose already installed"
    return 0
  fi

  require_command apt-get
  require_command curl
  require_command gpg
  require_command dpkg
  require_command systemctl

  log_step "host" "Installing Docker packages"
  apt-get update
  apt_install ca-certificates curl gnupg lsb-release ufw
  ensure_docker_repo
  apt-get update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

ensure_ssh_rule() {
  ssh_port=22
  if [ -r /etc/ssh/sshd_config ]; then
    configured_port=$(awk '$1 == "Port" {print $2; exit}' /etc/ssh/sshd_config)
    if [ -n "${configured_port:-}" ]; then
      ssh_port=$configured_port
    fi
  fi

  ufw allow "${ssh_port}/tcp"
}

ensure_ufw_rule() {
  rule=$1
  current_status=$(ufw status 2>/dev/null || true)
  printf '%s\n' "$current_status" | grep -q "$rule" || ufw allow "$rule"
}

configure_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    log_info "ufw is not installed, skipping firewall configuration"
    return 0
  fi

  log_step "host" "Configuring firewall rules"
  current_status=$(ufw status 2>/dev/null || true)
  if printf '%s\n' "$current_status" | grep -q "Status: inactive"; then
    ufw default deny incoming
    ufw default allow outgoing
    ensure_ssh_rule
  fi

  VLESS_PORT=${XRAY_VLESS_PORT:-8443}
  SOCKS_PORT=${XRAY_TELEGRAM_SOCKS_PORT:-29418}

  ensure_ufw_rule "${VLESS_PORT}/tcp"
  ensure_ufw_rule "${SOCKS_PORT}/tcp"
  ensure_ufw_rule "${SOCKS_PORT}/udp"
  ufw --force enable
}

main() {
  ensure_root
  require_supported_os
  load_env_if_present
  install_docker
  configure_firewall

  log_info "Host bootstrap completed."
}

main "$@"
