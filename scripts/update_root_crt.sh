#!/usr/bin/env bash
set -euo pipefail

# 初始化
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh


cd ${PROJECT_DIR}/services
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ${PROJECT_DIR}/services/my_caddy_root.crt
