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


# sudo fail2ban-client status sshd
info "current banned ip:"
sudo fail2ban-client banned

for jail in $(sudo fail2ban-client status | grep "Jail list" | sed "s/.*://;s/,//g"); do
    echo "=== $jail ==="
    sudo fail2ban-client get $jail banip --with-time
done
