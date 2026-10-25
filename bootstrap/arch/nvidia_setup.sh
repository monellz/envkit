#!/usr/bin/env bash
set -euo pipefail

# 需要以普通用户运行

# 初始化
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $SHELL_DIR))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

sudo pacman -S dkms linux-headers
sudo pacman -S nvidia-open-dkms 
sudo pacman -S nvtop

# 需要在早期启动阶段加载 NVIDIA 模块
# ref: https://wiki.archlinux.org/title/NVIDIA#Early_loading
USE_SUDO=1 copy $SHELL_DIR/etc/modules-load.d/nvidia.conf /etc/modules-load.d/nvidia.conf

