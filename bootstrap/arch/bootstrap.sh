#!/usr/bin/env bash
set -euo pipefail

# init
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $SHELL_DIR))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

# this script should be run by root 
# available network is necessary
if [[ "$EUID" -ne 0 ]]; then
    error "This script should be run by root"    
    exit -1
fi


SNAPSHOTS_DIR=/.snapshots

ts=$(date +%Y%m%d-%H%M%S)

# snapshot first
info "Snapshot all"
pacman -S --noconfirm rsync
# boot
rsync -a --mkpath --delete /boot/ "/.bootbackup/init_${ts}_boot"
btrfs subvolume snapshot -r / $SNAPSHOTS_DIR/init_${ts}_root
btrfs subvolume snapshot -r /home $SNAPSHOTS_DIR/init_${ts}-root

# dont update mirror here
# pacman mirror link
# copy $SHELL_DIR/etc/pacman.conf  /etc/pacman.conf
# copy $SHELL_DIR/etc/pacman.d/mirrorlist  /etc/pacman.d/mirrorlist



# locale
info "Adjust locale"
copy $SHELL_DIR/etc/locale.gen /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# time
info "Adjust time"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
timedatectl set-ntp true
hwclock --systohc --utc


# necessary packages
info "Install necessary packages"
pacman -S --noconfirm vim iwd git openssh
pacman -S --noconfirm grub efibootmgr
pacman -S --noconfirm os-prober

if grep -q "GenuineIntel" /proc/cpuinfo; then
    info "Install intel ucode"
    pacman -S --noconfirm intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    info "Install amd ucode"
    pacman -S --noconfirm amd-ucode
else
    error "Unsupported CPU"
    exit 1
fi

# network
info "Setup network"
copy $SHELL_DIR/etc/systemd/network/20-wired.network /etc/systemd/network/20-wired.network
copy $SHELL_DIR/etc/systemd/network/20-wireless.network /etc/systemd/network/20-wireless.network
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable iwd


info "Forbidden bee noise"
copy $SHELL_DIR/etc/modprobe.d/nobeep.conf /etc/modprobe.d/nobeep.conf


info "Grub install"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH
copy $SHELL_DIR/etc/default/grub /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

info "Setup sudoer"
copy $SHELL_DIR/etc/sudoers.d/10-wheel-nopasswd /etc/sudoers.d/10-wheel-nopasswd

info "Create user"
useradd -m -G wheel,audio,video,input,storage -s /bin/bash zrx || true
passwd zrx

ok "Root bootstrap finished"

