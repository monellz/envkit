#!/usr/bin/env bash
# Mac 上安装 / 启用 / 停用 sing-box（gate-plan 阶段 4）。需要 root。
#
#   sudo -E bash install_sing_box.sh install [tailscale 状态目录]
#                                              # 下载官方二进制、拉取配置、安装 launchd plist（不启动）
#                                              # 可选参数：已登录的 tailscale endpoint 状态目录（例如预演时的
#                                              # ~/.cache/sb-preflight/tailscale），复制过去后 macbook-sb 不用重新登录
#   sudo bash install_sing_box.sh enable       # 加载 launchd：启动 sing-box 和每小时同步
#   sudo bash install_sing_box.sh disable      # 卸载 launchd：停止 sing-box（回滚用）
#
# install 时要下载 GitHub release：先在当前 shell 执行 `proxy` 设置代理，再用 sudo -E 保留环境变量。
# 下载慢时可以先用浏览器下载 release 包，再用 SING_BOX_TARBALL 指定本地文件（同样会校验 sha256）：
#   sudo SING_BOX_TARBALL=~/Downloads/sing-box-1.14.4-darwin-amd64.tar.gz bash install_sing_box.sh install
# 建议 install 之后、enable 之前，先前台试运行（见 README.md）。
set -euo pipefail

VERSION=1.14.4
# 官方 release 的 sha256（GitHub release 页面的 digest）。
# 注意 macOS 自带 bash 3.2，不支持关联数组，所以用函数
release_sha256() {
    case "$1" in
        arm64) echo 0d8c7f5ed5d587b0f1a5e9772a708ec3bfa4ac4c9329604b01d8d9c2ba406838 ;;
        amd64) echo eae86b9b033bba50b7c44ab719e4bfac0aca05efd28483390ed3aa510f32db25 ;;
    esac
}

SHELL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENVKIT=$(cd "$SHELL_DIR/../.." && pwd)
. "$ENVKIT/scripts/color.sh"
. "$ENVKIT/scripts/log.sh"

LABEL=io.sagernet.sing-box
SYNC_LABEL=io.sagernet.sing-box-sync
DAEMONS=/Library/LaunchDaemons

[[ "$(uname -s)" == Darwin ]] || { error "只用于 macOS"; exit 1; }
[[ "$EUID" -eq 0 ]] || { error "需要 root：sudo bash $0 ${1:-}"; exit 1; }

install_binary() {
    local arch tarball tmp
    case "$(uname -m)" in
        arm64) arch=arm64 ;;
        x86_64) arch=amd64 ;;
        *) error "未知架构：$(uname -m)"; exit 1 ;;
    esac
    tarball=sing-box-$VERSION-darwin-$arch.tar.gz
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    if [[ -n "${SING_BOX_TARBALL:-}" ]]; then
        info "使用本地文件 $SING_BOX_TARBALL"
        cp "$SING_BOX_TARBALL" "$tmp/$tarball"
    else
        info "下载 $tarball"
        curl -fL --max-time 300 -o "$tmp/$tarball" \
            "https://github.com/SagerNet/sing-box/releases/download/v$VERSION/$tarball"
    fi
    echo "$(release_sha256 $arch)  $tmp/$tarball" | shasum -a 256 -c -
    tar -xzf "$tmp/$tarball" -C "$tmp"
    install -m 755 "$tmp/sing-box-$VERSION-darwin-$arch/sing-box" /usr/local/bin/sing-box
    ok "$(/usr/local/bin/sing-box version | head -1)"
}

cmd_install() {
    local ts_state=${1:-}
    # Homebrew 装的旧版 sing-box 是指向 Cellar 的软链接，直接覆盖会写进 Homebrew 的目录
    if [[ -L /usr/local/bin/sing-box ]]; then
        error "/usr/local/bin/sing-box 是软链接（$(readlink /usr/local/bin/sing-box)），请先用普通用户执行 brew uninstall sing-box"
        exit 1
    fi
    mkdir -p /usr/local/bin /usr/local/etc/sing-box /usr/local/var/lib/sing-box /usr/local/var/log
    chmod 700 /usr/local/var/lib/sing-box  # cache.db 和 tailscale 节点密钥
    install_binary

    # macOS 上 sing-box 内置的 tailscale endpoint（macbook-sb）的登录状态，
    # 位置对应配置里的 state_directory: "tailscale"（相对工作目录 -D）
    if [[ -n "$ts_state" ]]; then
        if [[ -e /usr/local/var/lib/sing-box/tailscale ]]; then
            warn "已存在 /usr/local/var/lib/sing-box/tailscale，不覆盖"
        else
            cp -R "$ts_state" /usr/local/var/lib/sing-box/tailscale
            chown -R root:wheel /usr/local/var/lib/sing-box/tailscale
            ok "已迁移 tailscale 状态：$ts_state"
        fi
    fi

    # 首次拉取配置：只下载并检查，不重启（此时 sing-box 还没有在 launchd 中运行）
    info "从 hub 拉取配置"
    SING_BOX_RESTART=true bash "$ENVKIT/scripts/sync_sing_box.sh" || true
    /usr/local/bin/sing-box check -c /usr/local/etc/sing-box/config.json

    # launchd plist：同步任务里的 __ENVKIT__ 替换成本机仓库路径
    install -m 644 -o root -g wheel "$SHELL_DIR/etc/$LABEL.plist" "$DAEMONS/$LABEL.plist"
    sed "s#__ENVKIT__#$ENVKIT#g" "$SHELL_DIR/etc/$SYNC_LABEL.plist" > "$DAEMONS/$SYNC_LABEL.plist"
    chown root:wheel "$DAEMONS/$SYNC_LABEL.plist"; chmod 644 "$DAEMONS/$SYNC_LABEL.plist"
    install -m 644 "$SHELL_DIR/etc/newsyslog-sing-box.conf" /etc/newsyslog.d/sing-box.conf
    ok "安装完成（尚未启动）。前台试运行：sudo sing-box run -c /usr/local/etc/sing-box/config.json -D /usr/local/var/lib/sing-box"
}

cmd_enable() {
    launchctl bootstrap system "$DAEMONS/$LABEL.plist"
    launchctl bootstrap system "$DAEMONS/$SYNC_LABEL.plist"
    ok "已启动；日志：/usr/local/var/log/sing-box.log"
}

cmd_disable() {
    launchctl bootout system/$SYNC_LABEL 2>/dev/null || true
    launchctl bootout system/$LABEL 2>/dev/null || true
    ok "已停止 sing-box 和同步任务"
}

case "${1:-}" in
    install) cmd_install "${2:-}" ;;
    enable) cmd_enable ;;
    disable) cmd_disable ;;
    *) echo "用法：sudo [-E] bash $0 install|enable|disable" >&2; exit 1 ;;
esac
