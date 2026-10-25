#!/usr/bin/env bash
set -euo pipefail

# 初始化
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $(dirname $SHELL_DIR)))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

sudo apt update
sudo apt install -y fail2ban python3-systemd

# 只保护 sshd：Web 服务都经 tailscale serve 只对 tailnet 开放，没有公网入口
USE_SUDO=1 link ${SHELL_DIR}/jail.local /etc/fail2ban/jail.local

# sudo systemctl restart fail2ban
sudo fail2ban-client reload
