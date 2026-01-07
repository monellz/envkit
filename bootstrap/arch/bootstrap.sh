#!/usr/bin/env bash
set -euo pipefail

# this script should be run by root 
# available network is necessary

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $SHELL_DIR))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh


SNAPSHOTS_DIR=/.snapshots

ts=$(date +$Y$m$d-$H$M$S)

# snapshot first
pacman -S rsync
# boot
rsync -a --mkpath --delete /boot/ "/.bootbackup/init_${ts}_boot"
btrfs subvolume snapshot -r / $SNAPSHOTS_DIR/init_${ts}_root
btrfs subvolume snapshot -r /home $SNAPSHOTS_DIR/init_${ts}-root

# dont update mirror here
# pacman mirror link
# copy $SHELL_DIR/etc/pacman.conf  /etc/pacman.conf
# copy $SHELL_DIR/etc/pacman.d/mirrorlist  /etc/pacman.d/mirrorlist


# necessary packages
pacman -S vim iwd git openssh
pacman -S grub efibootmgr
pacman -S os-prober


if grep -q "GenuineIntel" /proc/cpuinfo; then
    info "Install intel ucode"
    pacman -S intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    info "Install amd ucode"
    pacman -S amd-ucode
else
    error "Unsupported CPU"
    exit 1
fi

# time
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
timedatectl set-ntp true
hwclock --systohc --utc

# locale
localectl set-locale LANG=en.asdasd
localectl set-keymap us

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH
grub-mkconfig -o /boot/grub/grub.cfg

# user 
# useradd -m -G wheel,audio,video,input,storage -s /bin/bash zrx

