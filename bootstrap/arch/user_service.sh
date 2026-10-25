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



# ssh-agent
systemctl --user enable --now ssh-agent
ssh-add ~/.ssh/id_rsa
# ssh-add -l

# 声音
# sudo pacman -S pipewire-pulse pipewire-alsa
systemctl --user enable --now pipiewire-pulse
warn "Reboot is needed to make sound work well"


sudo pacman -S sddm
# sudo systemctl get-default
# 默认应该已经是 graphical
# sudo systemctl set-default graphical.target
sudo systemctl enable --now sddm
