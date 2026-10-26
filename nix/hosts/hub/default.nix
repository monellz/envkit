# hub：树莓派 4（8GB）。
# 系统装在 USB 设备上（EEPROM 启动顺序 USB 优先），原 SD 卡上的 Debian 保留作回滚。
{ ... }:

{
  imports = [
    ./hardware.nix
    ./base.nix
    ./secrets.nix
    ./network.nix
    ./auth-thu.nix
  ];

  networking.hostName = "hub";

  # 首次安装时的 NixOS 版本，用于有状态服务的数据格式兼容；之后不要随升级修改
  system.stateVersion = "26.05";
}
