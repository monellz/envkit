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

# 主机名
hostnamectl hostname myarch

# 网络 DNS
sudo systemctl enable --now systemd-networkd
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 链接 pacman 配置
USE_SUDO=1 link $SHELL_DIR/etc/pacman.conf  /etc/pacman.conf
USE_SUDO=1 link $SHELL_DIR/etc/pacman.d/mirrorlist  /etc/pacman.d/mirrorlist


# 关闭蜂鸣器
# sudo rmmod pcspkr || true
# /etc/modprobe.d/* 不能用软链接，所以放在 bootstrap.sh 里处理
# USE_SUDO=1 link $SHELL_DIR/etc/modprobe.d/nobeep.conf /etc/modprobe.d/nobeep.conf


# 必需的软件包
sudo pacman -S --noconfirm vim git fastfetch tree
sudo pacman -S --noconfirm openssh
sudo systemctl enable --now sshd


# Docker
sudo pacman -S --noconfirm docker docker-compose
sudo systemctl enable --now docker.service
sudo usermod -aG docker $USER
warn "Reboot is needed to correctly enable docker (verify by docker info)"
# /etc/systemd/* 不能用软链接，只能复制
USE_SUDO=1 copy $SHELL_DIR/etc/systemd/system/docker.service /etc/systemd/system/docker.service
USE_SUDO=1 link $SHELL_DIR/etc/docker/daemon.json /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
