# 磁盘与启动。所有文件系统都按标签 / UUID 挂载：从 USB 启动时数据盘可能从 sda 变成 sdb，
# 写死设备名可能挂错盘。
{ pkgs, ... }:

{
  # 用 nixpkgs 的主线 LTS 内核，而不是 nixos-hardware 默认的树莓派专用内核（linux-rpi）：
  # 主线内核已完整支持 Pi 4 的网卡、USB、SD 卡和温控，并且官方缓存里有现成的二进制；
  # 专用内核缓存里没有，在 Pi 上从源码编译要 8 小时以上。hub 不接显示器，用不到它的 GPU/摄像头支持
  boot.kernelPackages = pkgs.linuxPackages;

  # 系统盘：U 盘上的 NixOS 镜像。标签沿用 nixpkgs sd-image 的约定（镜像里的根分区就叫 NIXOS_SD）
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # 树莓派固件加载 U-Boot，再由 U-Boot 读取 extlinux 配置启动 NixOS；
  # 每次切换配置都会生成新的启动项，启动时可以选择上一代系统回滚
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # 数据盘：2TB USB 移动硬盘（btrfs，整盘）。没插时不影响开机
  fileSystems."/mnt/disk" = {
    device = "/dev/disk/by-uuid/c18ec6eb-c389-4887-9b73-670e623410f0";
    fsType = "btrfs";
    options = [ "nofail" "x-systemd.device-timeout=10" ];
  };
}
