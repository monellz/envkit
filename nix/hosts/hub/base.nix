# 基础设置：Nix、用户、ssh、时区。
{ pkgs, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # hub 在校园网内，清华 TUNA 镜像最快；失败时回退到官方缓存
    substituters = [
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
    ];
    trusted-users = [ "root" "zrx" ];
  };

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.zrx = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ../../keys/zrx.pub ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # 远程维护需要无密码 sudo（只能用 ssh 密钥登录）
  security.sudo.wheelNeedsPassword = false;

  # 公网 IP 上的 ssh 使用非标准端口 3333，只允许密钥登录
  services.openssh = {
    enable = true;
    ports = [ 3333 ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    htop
  ];
}
