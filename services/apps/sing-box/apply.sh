#!/usr/bin/env bash
# 安全切换 pi（gateway）上 sing-box 的配置/镜像，失败自动回滚。
#
# 用法：
#   apply.sh --detach [配置文件]   # 推荐：交给 systemd 执行，即使当前 SSH / Claude Code 会话断开也会跑完
#   apply.sh [配置文件]            # 在当前 shell 中直接执行
# 配置文件默认是 out/gateway.json。镜像版本以 services/compose.yml 中 sing-box 的 image 为准。
#
# 流程：
#   1. 用目标镜像执行 sing-box check，失败直接退出（什么都不改）
#   2. 把新配置和规则集（out/srs）放进 live/，重建 sing-box 容器
#   3. 自检：代理能连 Anthropic、出口不在国内、不走代理能访问 baidu
#   4. 自检通过：把当前镜像和配置记为 live/good/（下次回滚的目标）
#      自检失败：恢复 live/good/ 中的镜像和配置，重建容器后再自检一次。
#      只恢复 compose.yml 里 sing-box 的 image 这一行，不覆盖整个文件，以免把其他服务的改动一起回滚
#
# 为什么要这么麻烦：pi 上的 Claude Code 经 127.0.0.1:7890 访问 API，sing-box 起不来时会话无法自救。
set -uo pipefail

APP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SERVICES_DIR=$(cd "$APP_DIR/../.." && pwd)
COMPOSE_FILE=$SERVICES_DIR/compose.yml
LIVE=$APP_DIR/live          # 挂载进容器的 /conf（只读）
GOOD=$LIVE/good             # 上一次自检通过的镜像（image 文件）和配置
LOG=$LIVE/apply.log
PROXY=http://127.0.0.1:7890

if [[ "${1:-}" == "--detach" ]]; then
    shift
    cfg=$(realpath "${1:-$APP_DIR/out/gateway.json}")
    unit=sing-box-apply-$(date +%Y%m%d%H%M%S)
    echo "交给 systemd 执行：$unit，日志：$LOG"
    # --wait：当前 shell 等待结果；但进程归 systemd 管，会话断开也不会被杀掉
    exec systemd-run --user --wait --collect --quiet --unit="$unit" "$APP_DIR/apply.sh" "$cfg"
fi

CFG=$(realpath "${1:-$APP_DIR/out/gateway.json}")
mkdir -p "$LIVE" "$GOOD"
exec > >(tee -a "$LOG") 2>&1

# 同一时间只允许一个切换在跑
exec 9>"$LIVE/.apply.lock"
flock -n 9 || { echo "另一个 apply.sh 正在运行"; exit 1; }

log() { echo "[$(date '+%F %T')] $*"; }

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

# 当前 compose.yml 中 sing-box 的镜像
target_image() {
    compose config --format json sing-box \
        | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["services"]["sing-box"]["image"])'
}

# 重建 sing-box 容器。
# --no-deps 必须加：否则会连带重建 auth-thu，触发 auth-thu-deauth 让校园网下线
recreate() {
    compose up -d --no-deps --force-recreate sing-box
}

# 自检，全部通过返回 0
self_check() {
    local i code country
    for i in 1 2 3; do
        sleep 10
        log "自检第 $i 次"
        # 容器必须处于 running（不能是 restarting）
        if [[ "$(docker inspect -f '{{.State.Status}}' sing-box 2>/dev/null)" != running ]]; then
            log "  容器未运行"; continue
        fi
        # 1. Anthropic API 能连上（任意 HTTP 状态码都算，000 表示连接失败）
        code=$(curl -s -o /dev/null -w '%{http_code}' -x "$PROXY" --max-time 15 https://api.anthropic.com)
        log "  api.anthropic.com via 7890: $code"
        [[ "$code" == 000 ]] && continue
        # 2. Claude 实际使用的出口（ai-critical -> proxy-ai）不在国内。
        #    claude.ai 在 Cloudflare 后面，/cdn-cgi/trace 会返回出口所在地 loc=XX。
        #    注意不要用 ipinfo.io 之类的地址：它不在 geolocation-!cn 里，本来就走直连
        country=$(curl -s -x "$PROXY" --max-time 15 https://claude.ai/cdn-cgi/trace | sed -n 's/^loc=//p')
        log "  claude.ai 出口: ${country:-<空>}"
        [[ -z "$country" || "$country" == CN ]] && continue
        # 3. 不走代理也能访问国内网站（TUN 和校园网正常）
        if ! curl -s -o /dev/null --noproxy '*' --max-time 10 https://www.baidu.com; then
            log "  直连 baidu 失败"; continue
        fi
        return 0
    done
    return 1
}

log "===== 开始切换：$CFG"
IMAGE=$(target_image) || { log "读取 compose.yml 失败"; exit 1; }
log "目标镜像：$IMAGE"

# 1. check（一次性容器，--network none，不影响宿主机）
if ! docker run --rm --network none -v "$CFG:/c.json:ro" "$IMAGE" check -c /c.json; then
    log "sing-box check 失败，未做任何改动"; exit 1
fi

# 2. 放入新配置（先写临时文件再 mv，保证容器读到的是完整文件）
[[ -f "$LIVE/gateway.json" ]] && cp -a "$LIVE/gateway.json" "$LIVE/gateway.json.prev"
cp "$CFG" "$LIVE/gateway.json.tmp" && mv "$LIVE/gateway.json.tmp" "$LIVE/gateway.json"
if [[ -d "$APP_DIR/out/srs" ]]; then
    mkdir -p "$LIVE/srs" && cp -a "$APP_DIR/out/srs/." "$LIVE/srs/"
fi

log "重建 sing-box 容器"
recreate
if self_check; then
    cp -a "$LIVE/gateway.json" "$GOOD/gateway.json"
    echo "$IMAGE" > "$GOOD/image"
    log "RESULT: OK"
    exit 0
fi

# 3. 回滚
log "自检失败，最近日志："
docker logs --tail 30 sing-box 2>&1 | sed 's/^/    /'
log "回滚到 live/good/"
if [[ -f "$GOOD/image" ]] && [[ "$(cat "$GOOD/image")" != "$IMAGE" ]]; then
    good_image=$(cat "$GOOD/image")
    # compose.yml 中只有 sing-box 使用这个镜像仓库，按完整的 image 行替换
    sed -i "s#^\(\s*image: \)$IMAGE\$#\1$good_image#" "$COMPOSE_FILE"
    log "compose.yml 中 sing-box 的镜像已恢复为 $good_image"
fi
[[ -f "$GOOD/gateway.json" ]] && cp -a "$GOOD/gateway.json" "$LIVE/gateway.json"
recreate
if self_check; then
    log "RESULT: ROLLED_BACK（回滚成功）"
else
    log "RESULT: ROLLBACK_FAILED（回滚后自检仍失败，需要人工处理）"
fi
exit 1
