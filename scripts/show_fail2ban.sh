#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh


info "fail2ban"
grep -E "Found|Ban|Unban" /var/log/fail2ban.log

info "qbit"
grep -E "login failure" ~/disk/qbit/config/qBittorrent/data/logs/qbittorrent.log
