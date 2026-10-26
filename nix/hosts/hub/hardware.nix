# 磁盘与启动。所有文件系统都按 UUID 挂载：从 USB 启动时设备名（sda/sdb）可能变化，写死设备名可能挂错盘。
#
# 根文件系统在数据盘（2TB USB 移动硬盘，btrfs）的子卷 @nixos 上；SD 卡保留原来的 Debian 作为回退系统。
# 启动：树莓派固件直接加载 SD 卡启动分区里的内核（不经过 U-Boot），用 hub-boot 管理两个启动位，
# 新系统先用 tryboot 试启动，确认可用后才成为默认（见 pkgs/hub-boot/hub-boot.sh）。
# 远程维护时没有人能到现场，所以各种失败都要能自动重启，回到上一个可用的系统：
#   内核崩溃 / initrd 找不到根分区   panic=10 + boot.panic_on_fail
#   系统卡死                         硬件看门狗
#   起来了但连不进来                 试启动后超时未确认自动重启（hub-boot-guard）
{ pkgs, ... }:

let
  dataDiskUuid = "c18ec6eb-c389-4887-9b73-670e623410f0";
  # 试启动后多久没确认就自动重启
  confirmTimeout = "15min";
in
{
  # 用 nixpkgs 的主线 LTS 内核，而不是 nixos-hardware 默认的树莓派专用内核（linux-rpi）：
  # 主线内核已完整支持 Pi 4 的网卡、USB、SD 卡和温控，并且官方缓存里有现成的二进制；
  # 专用内核缓存里没有，在 Pi 上从源码编译要 8 小时以上。hub 不接显示器，用不到它的 GPU/摄像头支持
  boot.kernelPackages = pkgs.linuxPackages;

  # initrd 里要能访问 USB 移动硬盘：Pi 4 的 USB 控制器挂在 PCIe 上
  boot.initrd.availableKernelModules = [ "pcie_brcmstb" "reset_raspberrypi" "xhci_pci" "usb_storage" "uas" "usbhid" ];

  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
    # 内核崩溃 10 秒后重启；initrd 阶段出错（例如找不到根分区）也按崩溃处理
    "panic=10"
    "boot.panic_on_fail"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${dataDiskUuid}";
    fsType = "btrfs";
    options = [ "subvol=@nixos" "noatime" ];
  };

  # 数据盘的顶层（gitea / vaultwarden / webdav 等数据，见 data.nix）。和根文件系统是同一块盘，
  # 盘不在时系统本身也起不来，所以这里不需要 nofail
  fileSystems."/mnt/disk" = {
    device = "/dev/disk/by-uuid/${dataDiskUuid}";
    fsType = "btrfs";
    options = [ "subvol=/" "noatime" ];
  };

  # SD 卡启动分区：固件、两个启动位（nixos/、nixos-try/）、config.txt / tryboot.txt
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-uuid/4C33-F302";
    fsType = "vfat";
    options = [ "nofail" "umask=0077" ];
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.loader.external = {
    enable = true;
    # nixos-rebuild switch / boot 时把新系统写进 nixos-try/；执行 hub-boot try 才会真正试启动
    installHook = "${pkgs.hub-boot}/bin/hub-boot install";
  };
  environment.systemPackages = [ pkgs.hub-boot ];

  # 硬件看门狗：systemd 定期喂狗，系统卡死超过 30 秒就由硬件重启
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  # 试启动时开始倒计时，超时未执行 hub-boot confirm 就自动重启（回到 config.txt 指向的系统）
  systemd.services.hub-boot-guard = {
    description = "Reboot back to the confirmed system unless this tryboot is confirmed";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      f=/proc/device-tree/chosen/bootloader/tryboot
      if [ -e "$f" ] && [ "$(${pkgs.coreutils}/bin/od -An -tu4 --endian=big "$f" | ${pkgs.coreutils}/bin/tr -d ' ')" = 1 ]; then
        echo "本次是试启动：${confirmTimeout} 内未执行 hub-boot confirm 将自动重启"
        ${pkgs.systemd}/bin/systemd-run --unit=hub-boot-revert --on-active=${confirmTimeout} \
          ${pkgs.systemd}/bin/systemctl reboot
      fi
    '';
  };
}
