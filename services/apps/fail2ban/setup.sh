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

for f in ${SHELL_DIR}/filter.d/*; do
    USE_SUDO=1 link $f /etc/fail2ban/filter.d/$(basename $f)
done

for f in ${SHELL_DIR}/jail.d/*; do
    USE_SUDO=1 link $f /etc/fail2ban/jail.d/$(basename $f)
done

# sudo systemctl restart fail2ban
sudo fail2ban-client reload
