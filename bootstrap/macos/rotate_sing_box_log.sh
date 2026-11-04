#!/usr/bin/env bash
# 轮转 sing-box.log：复制一份压缩，再把原文件清空（copytruncate）。
#
# 为什么不用 newsyslog：sing-box 的输出由 launchd 在启动时打开（plist 的 StandardOutPath），
# newsyslog 把文件改名后，sing-box 仍写进旧文件（已改名、压缩后被删除），新的 sing-box.log 一直是空的。
# 通知进程重新打开日志也不行（文件由 launchd 打开），macOS 的 newsyslog 又没有 copytruncate。
# 清空原文件而不改名，sing-box 就能继续写同一个文件。
#
# 由 launchd（io.sagernet.sing-box-logrotate）每 10 分钟以 root 运行。
# 文件命名和原来 newsyslog 一致：sing-box.log.0.bz2（最新）… .4.bz2
set -euo pipefail

LOG=${SING_BOX_LOG:-/usr/local/var/log/sing-box.log}
MAX_KB=${SING_BOX_LOG_MAX_KB:-10240}
KEEP=${SING_BOX_LOG_KEEP:-5}

[[ -f "$LOG" ]] || exit 0
size=$(stat -f %z "$LOG")
(( size > MAX_KB * 1024 )) || exit 0

echo "$(date '+%F %T') 轮转 ${LOG}（${size} 字节）"

# 旧的依次后移，最旧的删除
rm -f "$LOG.$((KEEP - 1)).bz2"
for ((i = KEEP - 2; i >= 0; i--)); do
    [[ -f "$LOG.$i.bz2" ]] && mv -f "$LOG.$i.bz2" "$LOG.$((i + 1)).bz2"
done

# 复制后清空。复制和清空之间写入的几行会丢失，可以接受
cp -p "$LOG" "$LOG.0"
: > "$LOG"
bzip2 -f "$LOG.0"

# 自检：launchd 应以追加方式（O_APPEND）打开日志，清空后 sing-box 从文件开头接着写。
# 如果不是追加方式，sing-box 会在原来的偏移处继续写，文件开头变成空洞（读出来是 \0）
sleep 2
if [[ -s "$LOG" && "$(head -c 1 "$LOG" | od -An -tx1 | tr -d ' ')" == 00 ]]; then
    echo "$(date '+%F %T') [WARN] 清空后文件开头是空洞：日志不是以追加方式打开的，copytruncate 不适用" >&2
fi
