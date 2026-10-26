# hub-boot：用树莓派固件的 tryboot 安全地切换 hub 的系统，新系统起不来时自动回到上一个可用的系统。
#
# SD 卡启动分区（/boot/firmware）上有两个启动位，固件直接加载其中的内核（不经过 U-Boot）：
#   nixos/       已确认可用的系统；config.txt 指向它
#   nixos-try/   待试启动的系统；tryboot.txt 指向它
# tryboot.txt 只在执行 `reboot '0 tryboot'` 后的那一次开机生效，之后任何一次重启都回到 config.txt。
#
# 用法：
#   hub-boot install <系统路径>   把系统写进 nixos-try/（nixos-rebuild 安装引导时自动调用）
#   hub-boot try                  重启并试启动 nixos-try/
#   hub-boot confirm              把当前启动的系统提升为 nixos/（取消超时自动重启）
#   hub-boot status               查看两个启动位和本次是否为试启动
#
# 试启动后如果一直不执行 confirm，hub-boot-guard 会在超时后自动重启，回到 config.txt 指向的系统。
# 首次从 Debian 迁移时，config.txt 还是 Debian 的；第一次 confirm 会把它另存为 config-debian.txt。
set -euo pipefail

FW=/boot/firmware
MAIN=$FW/nixos
TRY=$FW/nixos-try

die() { echo "hub-boot: $*" >&2; exit 1; }

# 固件写给系统的设备树里记录了本次是否为 tryboot 启动
is_tryboot() {
  local f=/proc/device-tree/chosen/bootloader/tryboot
  [[ -e $f ]] && [[ "$(od -An -tu4 --endian=big "$f" | tr -d ' ')" == 1 ]]
}

# 固件配置：直接加载启动位里的内核、initrd 和设备树（主线内核用主线设备树，upstream_kernel=1 让固件按主线内核的约定工作）
fw_config() {
  local slot=$1
  cat <<EOF
# 由 hub-boot 生成：启动 NixOS（${slot}/）
[all]
arm_64bit=1
upstream_kernel=1
enable_uart=1
kernel=${slot}/Image
initramfs ${slot}/initrd followkernel
device_tree=${slot}/bcm2711-rpi-4-b.dtb
cmdline=${slot}/cmdline.txt
EOF
}

cmd_install() {
  local system=${1:?用法：hub-boot install <系统路径>}
  [[ -e $system/init && -e $system/kernel && -e $system/initrd ]] || die "不是有效的 NixOS 系统：$system"
  mountpoint -q "$FW" || die "$FW 没有挂载"
  local tmp=$FW/.nixos-try.tmp
  rm -rf "$tmp"
  mkdir -p "$tmp"
  cp "$system/kernel" "$tmp/Image"
  cp "$system/initrd" "$tmp/initrd"
  cp "$system/dtbs/broadcom/bcm2711-rpi-4-b.dtb" "$tmp/"
  # panic=10 和 boot.panic_on_fail（在 kernel-params 中）：启动失败时自动重启，回到 config.txt 指向的系统
  echo "init=$system/init $(cat "$system/kernel-params")" > "$tmp/cmdline.txt"
  echo "$system" > "$tmp/system"
  sync
  rm -rf "$TRY"
  mv "$tmp" "$TRY"
  fw_config nixos-try > "$FW/tryboot.txt"
  sync
  echo "已写入 $TRY（$system）；执行 hub-boot try 试启动"
}

cmd_try() {
  [[ -e $TRY/system ]] || die "nixos-try/ 为空，先部署（nixos-rebuild boot）"
  echo "重启并试启动 $(cat "$TRY/system")"
  systemctl reboot --reboot-argument="0 tryboot"
}

cmd_confirm() {
  is_tryboot || die "本次不是试启动；只能确认经 hub-boot try 启动、验证过的系统"
  [[ -e $TRY/system ]] || die "nixos-try/ 为空"
  local booted
  booted=$(readlink -f /run/booted-system)
  [[ "$(cat "$TRY/system")" == "$booted" ]] || die "nixos-try/ 已被新的部署覆盖，和当前启动的系统不一致"
  # 先停掉超时自动重启
  systemctl stop hub-boot-revert.timer 2>/dev/null || true
  if [[ ! -e $FW/config-debian.txt ]] && ! grep -q '^# 由 hub-boot 生成' "$FW/config.txt"; then
    cp "$FW/config.txt" "$FW/config-debian.txt"
    echo "原 config.txt 已另存为 config-debian.txt（回到 Debian：把它复制回 config.txt 后重启）"
  fi
  rm -rf "$FW/.nixos.tmp"
  cp -r "$TRY" "$FW/.nixos.tmp"
  sync
  rm -rf "$MAIN"
  mv "$FW/.nixos.tmp" "$MAIN"
  fw_config nixos > "$FW/.config.txt.tmp"
  sync
  mv "$FW/.config.txt.tmp" "$FW/config.txt"
  sync
  echo "已确认：$booted 成为默认启动的系统"
}

cmd_status() {
  echo "本次启动：$(is_tryboot && echo 试启动 || echo 正常启动)  $(readlink -f /run/booted-system)"
  echo "nixos/（默认）：$(cat "$MAIN/system" 2>/dev/null || echo 无)"
  echo "nixos-try/   ：$(cat "$TRY/system" 2>/dev/null || echo 无)"
  echo "config.txt   ：$(grep -q '^# 由 hub-boot 生成' "$FW/config.txt" && echo NixOS || echo 其他系统（Debian）)"
  systemctl list-timers hub-boot-revert.timer --no-pager 2>/dev/null | sed -n 2p || true
}

case "${1:-}" in
  install) shift; cmd_install "$@" ;;
  try) cmd_try ;;
  confirm) cmd_confirm ;;
  status) cmd_status ;;
  *)
    cat >&2 <<'USAGE'
用法：
  hub-boot install <系统路径>   把系统写进 nixos-try/（nixos-rebuild 安装引导时自动调用）
  hub-boot try                  重启并试启动 nixos-try/
  hub-boot confirm              把当前启动的系统提升为 nixos/（取消超时自动重启）
  hub-boot status               查看两个启动位和本次是否为试启动
USAGE
    exit 1 ;;
esac
