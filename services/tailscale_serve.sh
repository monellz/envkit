#!/usr/bin/env bash
# hub 对 tailnet 提供的全部 Web / TCP 服务（tailscale serve，只有 tailnet 内设备能访问）。
#
# tailscale serve 的配置保存在 tailscaled 自己的状态里，不在仓库中；这个脚本是它的唯一来源。
# 每条命令只覆盖对应路径 / 端口的规则，可以重复执行；换机器后执行一次即可恢复。
# 用法：sudo ./tailscale_serve.sh（serve 配置中含有本地目录的发布时，tailscaled 要求所有修改都由 root 执行）。
#
# 地址：https://<本机 MagicDNS 名>/...，证书由 Tailscale 自动签发（Let's Encrypt），各设备无需额外信任。
#
# 关于路径前缀：--set-path=/x 转发到 http://127.0.0.1:端口 时，后端收到的路径会去掉 /x；
# 如果后端要求保留前缀（应用自己把路由挂在 /x 下），就在目标地址末尾写上 /x，把前缀加回来。
set -euo pipefail

[[ "$EUID" -eq 0 ]] || { echo "需要 root：sudo $0" >&2; exit 1; }

ENVKIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

serve() { tailscale serve --bg "$@" >/dev/null; }

# agents-hub（不在本仓库中管理）
serve --set-path=/ http://127.0.0.1:8700

# sing-box 客户端配置（generator 生成到 out/public，生成即发布）
serve --set-path=/sing-box "$ENVKIT/services/apps/sing-box/out/public"

# gitea：路由挂在根路径，ROOT_URL 中的 /gitea/ 只用于生成链接，所以去掉前缀
serve --set-path=/gitea http://127.0.0.1:8083

# vaultwarden：DOMAIN 带 /vault 时路由都挂在 /vault 下，所以保留前缀
serve --set-path=/vault http://127.0.0.1:8082/vault

# WebDAV（rclone serve webdav --baseurl /dav）：同样保留前缀
serve --set-path=/dav http://127.0.0.1:8084/dav

# gitea 内置的 ssh 服务：git remote 用 ssh 配置里的别名 gitea（hub:10022）
serve --tcp=10022 tcp://127.0.0.1:10022

tailscale serve status
