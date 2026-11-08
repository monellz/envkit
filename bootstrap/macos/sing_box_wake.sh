#!/usr/bin/env bash
# Mac 睡眠唤醒后重启 sing-box。
#
# 为什么需要：sing-box 内置的 tailscale endpoint（macbook-sb）睡醒后不会重新探测并发布自己的外部地址，
# 对端拿着过期的地址打不通，只能走 DERP 中继；重启 sing-box 会重新探测，马上恢复直连。
# 固定 listen_port 解决不了：路由器的 NAT 映射在睡眠期间过期，醒来后对外端口照样会变。
#
# 怎么判断睡醒：每 INTERVAL 秒记一次时间。睡眠期间循环停住，醒来后两次之间的间隔会远大于 INTERVAL。
# 重启前先等网络恢复（有默认路由、能解析域名），否则重启后探测到的仍是无效地址。
#
# 由 launchd（io.sagernet.sing-box-wake）常驻运行，以 root 身份。
set -uo pipefail

INTERVAL=${SING_BOX_WAKE_INTERVAL:-30}
GAP=${SING_BOX_WAKE_GAP:-120}           # 间隔超过这个秒数才算睡醒（合盖不到 2 分钟不重启）
SETTLE=${SING_BOX_WAKE_SETTLE:-10}      # 网络恢复后再等几秒，等 Wi-Fi、DHCP 稳定
LABEL=io.sagernet.sing-box
RESTART=${SING_BOX_RESTART:-launchctl kickstart -k system/$LABEL}

log() { echo "$(date '+%F %T') [wake] $*"; }

network_ready() {
    route -n get default >/dev/null 2>&1 && dscacheutil -q host -a name controlplane.tailscale.com | grep -q address
}

prev=$(date +%s)
while sleep "$INTERVAL"; do
    now=$(date +%s)
    if (( now - prev > GAP )); then
        log "检测到睡眠唤醒（间隔 $((now - prev)) 秒）"
        # 等到网络恢复为止；等待期间再次睡眠也没关系，醒来后接着等
        waited=0
        until network_ready; do
            sleep 5; waited=$((waited + 5))
            (( waited % 60 == 0 )) && log "仍在等待网络（${waited} 秒）"
        done
        sleep "$SETTLE"
        # sing-box 被 disable（launchd 里没有）时不拉起
        if [[ -n "${SING_BOX_RESTART:-}" ]] || launchctl print "system/$LABEL" >/dev/null 2>&1; then
            log "网络已恢复，重启 sing-box"
            $RESTART || log "[WARN] 重启失败"
        else
            log "sing-box 未加载，跳过"
        fi
    fi
    prev=$(date +%s)
done
