#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

NAME=my_caddy_root.crt
CRT=${PROJECT_DIR}/services/$NAME
if [[ -z "$CRT" || ! -f "$CRT" ]]; then
  error "$CRT not found or not a file"
  exit 1
fi

OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  # macOS
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CRT"
  ok "Installed on mac"
elif command -v update-ca-certificates >/dev/null 2>&1; then
  # Debian/Ubuntu/Raspberry Pi OS
  sudo install -m 0644 "$CRT" "/usr/local/share/ca-certificates/$NAME"
  info "$CRT: Saved to /usr/local/share/ca-certificated/$NAME"
  sudo update-ca-certificates
  ok "Installed on Debian"
elif command -v update-ca-trust >/dev/null 2>&1; then
  # Arch (p11-kit)
  sudo install -m 0644 "$CRT" "/etc/ca-certificates/trust-source/anchors/$NAME"
  info "$CRT: Saved to /etc/ca-certificates/trust-source/anchors/$NAME"
  sudo update-ca-trust extract
  ok "Installed to Arch"
else
  error "Unknown OS: $OS"
  exit 1
fi
