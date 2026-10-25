#!/usr/bin/env bash
set -euo pipefail

# 初始化
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $SHELL_DIR)
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

# 从自建的 vaultwarden 取 git-crypt 密钥。vault 只对 tailnet 开放，所以新机器要先装好 Tailscale 并登录；
# 地址用的是 Tailscale 签发的正规证书，不需要额外信任 CA

ITEM_ID=5a22ab82-39b8-4169-b77c-a32287cbd28e

bw config server https://hub.angora-wall.ts.net/vault

bw login || true

bw get attachment git-crypt.key --itemid $ITEM_ID --output ${PROJECT_DIR}/
info "Get git-crypt.key"

bw logout

ok "Use git-crypt unlock ${PROJECT_DIR}/git-crypt.key"
