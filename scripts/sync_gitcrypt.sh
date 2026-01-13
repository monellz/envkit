#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh


export NODE_EXTRA_CA_CERTS=${PROJECT_DIR}/services/my_caddy_root.crt

ITEM_ID=5a22ab82-39b8-4169-b77c-a32287cbd28e

bw config server https://166.111.238.16:8443/vault

bw login || true

bw get attachment git-crypt.key --itemid $ITEM_ID --output ${PROJECT_DIR}/
info "Get git-crypt.key"

bw logout

ok "Use git-crypt unlock ${PROJECT_DIR}/git-crypt.key"
