#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" || "$1" == -* ]]; then
    echo "用法: $0 <机器名称>" >&2
    echo "示例: $0 my-server" >&2
    exit 1
fi

REMOTE_PORT=9870
LOCAL_PORT=7890

exec ssh -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -R 127.0.0.1:${REMOTE_PORT}:127.0.0.1:${LOCAL_PORT} \
    "$1"
