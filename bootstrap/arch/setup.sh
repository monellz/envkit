#!/usr/bin/env bash
set -euo pipefail

# this script should be run by user

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $SHELL_DIR))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

# hostname
hostnamectl hostname myarch

# network dns
sudo systemctl enable --now systemd-networkd
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# link pacman setting
USE_SUDO=1 link $SHELL_DIR/etc/pacman.conf  /etc/pacman.conf
USE_SUDO=1 link $SHELL_DIR/etc/pacman.d/mirrorlist  /etc/pacman.d/mirrorlist


# no bell
sudo rmmod pcspkr || true
USE_SUDO=1 link $SHELL_DIR/etc/modprobe.d/nobeep.conf /etc/modprobe.d/nobeep.conf


# necessary packages
sudo pacman -S --noconfirm vim git fastfetch tree
sudo pacman -S --noconfirm openssh
sudo systemctl enable --now sshd


# docker
sudo pacman -S --noconfirm docker docker-compose
sudo systemctl enable --now docker.service
sudo usermod -aG docker $USER
warn "Reboot is needed to correctly enable docker (verify by docker info)"
USE_SUDO=1 link $SHELL_DIR/etc/docker/daemon.json /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
