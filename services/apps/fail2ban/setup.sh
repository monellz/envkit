#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $(dirname $SHELL_DIR)))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

sudo apt update
sudo apt install -y fail2ban python3-systemd

USE_SUDO=1 link ${SHELL_DIR}/jail.local /etc/fail2ban/jail.local

USE_SUDO=1 link ${SHELL_DIR}/filter.d/caddy-webdav.conf /etc/fail2ban/filter.d/caddy-webdav.conf
USE_SUDO=1 link ${SHELL_DIR}/filter.d/caddy-qbit.conf /etc/fail2ban/filter.d/caddy-qbit.conf
USE_SUDO=1 link ${SHELL_DIR}/filter.d/jellyfin.conf /etc/fail2ban/filter.d/jellyfin.conf
USE_SUDO=1 link ${SHELL_DIR}/filter.d/vaultwarden.conf /etc/fail2ban/filter.d/vaultwarden.conf

USE_SUDO=1 link ${SHELL_DIR}/jail.d/caddy-webdav.local /etc/fail2ban/jail.d/caddy-webdav.local
USE_SUDO=1 link ${SHELL_DIR}/jail.d/caddy-qbit.local /etc/fail2ban/jail.d/caddy-qbit.local
USE_SUDO=1 link ${SHELL_DIR}/jail.d/jellyfin.local /etc/fail2ban/jail.d/jellyfin.local
USE_SUDO=1 link ${SHELL_DIR}/jail.d/vaultwarden.local /etc/fail2ban/jail.d/vaultwarden.local




# sudo systemctl restart fail2ban
sudo fail2ban-client reload
