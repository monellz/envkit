#!/usr/bin/env bash
set -euo pipefail

# 初始化
SHELL_DIR=$(dirname $(readlink -f "$0"))
PROJECT_DIR=$(dirname $(dirname $SHELL_DIR))
SCRIPTS_DIR=$PROJECT_DIR/scripts
. ${SCRIPTS_DIR}/color.sh
. ${SCRIPTS_DIR}/log.sh
. ${SCRIPTS_DIR}/func.sh

# 需要以 root 运行
# 需要已经能联网
if [[ "$EUID" -ne 0 ]]; then
    error "This script should be run by root"    
    exit -1
fi


SNAPSHOTS_DIR=/.snapshots

ts=$(date +%Y%m%d-%H%M%S)

# 先做快照
info "Snapshot all"
pacman -S --noconfirm rsync
# 引导
rsync -a --mkpath --delete /boot/ "/.bootbackup/init_${ts}_boot"
btrfs subvolume snapshot -r / $SNAPSHOTS_DIR/init_${ts}_root
btrfs subvolume snapshot -r /home $SNAPSHOTS_DIR/init_${ts}-root

# 这里不更新镜像源
# pacman 镜像源
# copy $SHELL_DIR/etc/pacman.conf  /etc/pacman.conf
# copy $SHELL_DIR/etc/pacman.d/mirrorlist  /etc/pacman.d/mirrorlist



# 语言环境
info "Adjust locale"
copy $SHELL_DIR/etc/locale.gen /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# 时间
info "Adjust time"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
timedatectl set-ntp true
hwclock --systohc --utc


# 必需的软件包
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

# 网络
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

