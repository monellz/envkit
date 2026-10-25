#!/usr/bin/env bash
# 手动更新 sing-box 配置（不设定时任务，需要时自己运行）：
#   ./update.sh            用 secrets/subscription.b64 重新生成全部配置
#   ./update.sh --fetch    先按 secrets/subscription.env 的 SUB_URL 拉订阅，再生成
# 其余参数原样传给生成器（例如 --link <url>，见 python3 -m generator -h）。
#
# 流程：
#   1. 生成 out/gateway.json 和 out/public/*.json（每份都先 sing-box check）
#   2. out/public 由 tailscale serve 直接发布在 https://hub.<tailnet>.ts.net/sing-box/，
#      生成即发布；Mac/Arch 用 scripts/sync_sing_box.sh 拉取，手机由 SFA 远程 profile 自动更新
#   3. gateway 配置有变化时，用 apply.sh 切换 hub（自检失败会自动回滚）
#   4. --fetch 更新了订阅时，提醒提交 secrets/subscription.b64（git-crypt 加密）
set -euo pipefail

APP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$APP_DIR"

python3 -m generator "$@"

if cmp -s out/gateway.json live/gateway.json; then
    echo "gateway 配置没有变化，不需要切换"
else
    ./apply.sh --detach out/gateway.json
fi

if ! git diff --quiet -- secrets/subscription.b64; then
    echo "订阅内容有更新，记得提交：git add secrets/subscription.b64 && git commit"
fi
