#!/usr/bin/env bash
# 客户端（Mac / Arch PC）同步 hub 发布的 sing-box 配置（gate-plan 5.7）。
#
# 用法：sync_sing_box.sh [配置名]
#   配置名默认按系统选择：macOS -> client-macos，Linux -> client-linux
#
# 流程：下载 -> sing-box check -> 和本地配置对比 -> 有变化才替换并重启 -> 自检，失败则恢复旧配置
# 由 launchd（Mac）/ systemd timer（Arch）定时以 root 运行，也可以手动执行。
#
# 可用环境变量覆盖的默认值：
#   SING_BOX_URL     发布地址前缀（tailnet 改名后需要修改）
#   SING_BOX_CONFIG  本地配置文件路径
#   SING_BOX_BIN     sing-box 可执行文件（用于 check）
#   SING_BOX_RESTART 重启 sing-box 的命令
set -euo pipefail

SCRIPTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SCRIPTS_DIR/color.sh"
. "$SCRIPTS_DIR/log.sh"

BASE_URL=${SING_BOX_URL:-https://hub.angora-wall.ts.net/sing-box}

case "$(uname -s)" in
    Darwin)
        NAME=${1:-client-macos}
        CONFIG=${SING_BOX_CONFIG:-/usr/local/etc/sing-box/config.json}
        BIN=${SING_BOX_BIN:-/usr/local/bin/sing-box}
        # launchd 的 label 见 dotfiles 中的 plist（阶段 4）
        RESTART=${SING_BOX_RESTART:-launchctl kickstart -k system/io.sagernet.sing-box}
        ;;
    Linux)
        NAME=${1:-client-linux}
        CONFIG=${SING_BOX_CONFIG:-/etc/sing-box/config.json}
        BIN=${SING_BOX_BIN:-sing-box}
        RESTART=${SING_BOX_RESTART:-docker restart sing-box}
        ;;
    *)
        error "unsupported OS: $(uname -s)"; exit 1 ;;
esac

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# 1. 下载。经 Tailscale 直连 hub，不走任何 HTTP 代理（sing-box 挂了也能更新）
info "下载 $BASE_URL/$NAME.json"
curl -fsS --noproxy '*' --max-time 30 -o "$TMP" "$BASE_URL/$NAME.json"

# 2. 用本机的 sing-box 检查，版本不一致导致的不兼容在这里就会暴露
"$BIN" check -c "$TMP"

# 3. 没有变化就结束
if [[ -f "$CONFIG" ]] && cmp -s "$TMP" "$CONFIG"; then
    ok "配置没有变化"
    exit 0
fi

# 4. 替换并重启；旧配置保留为 .prev
mkdir -p "$(dirname "$CONFIG")"
[[ -f "$CONFIG" ]] && cp -p "$CONFIG" "$CONFIG.prev"
install -m 600 "$TMP" "$CONFIG"
info "配置已更新，重启 sing-box"
$RESTART

# 5. 自检：claude.ai 经本机代理能访问，且出口不在国内（同 hub 上的 apply.sh）
check_ok() {
    local loc
    loc=$(curl -s -x http://127.0.0.1:7890 --max-time 15 https://claude.ai/cdn-cgi/trace | sed -n 's/^loc=//p')
    [[ -n "$loc" && "$loc" != CN ]]
}
for _ in 1 2 3; do
    sleep 5
    if check_ok; then ok "自检通过"; exit 0; fi
done

# 6. 自检失败：恢复旧配置
error "自检失败，恢复旧配置"
if [[ -f "$CONFIG.prev" ]]; then
    cp -p "$CONFIG.prev" "$CONFIG"
    $RESTART
fi
exit 1
