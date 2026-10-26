# vaultwarden（自建 Bitwarden）：只对 tailnet 提供（tailscale serve 的 /vault），本身只监听 127.0.0.1。
# 数据目录 /var/lib/vaultwarden 是数据盘的 bind mount（见 data.nix）：db.sqlite3、rsa_key.pem（登录令牌签名密钥）、附件等。
# git-crypt 的密钥也存在这里，新机器解锁仓库前要先加入 tailnet 才能取到。
{ config, ... }:

{
  # ADMIN_TOKEN=...（管理后台 /vault/admin 的令牌哈希），以环境变量文件的形式提供
  sops.secrets."vaultwarden/env" = {
    restartUnits = [ "vaultwarden.service" ];
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    environmentFile = [ config.sops.secrets."vaultwarden/env".path ];
    config = {
      # 路由挂在 /vault 下（tailscale serve 转发时保留 /vault 前缀）
      DOMAIN = "https://hub.angora-wall.ts.net/vault";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8082;
      # tailscale serve 用 X-Forwarded-For 传客户端地址（默认读的 X-Real-IP 没有）
      IP_HEADER = "X-Forwarded-For";
    };
  };

  # 数据盘没挂上时不启动（见 data.nix）
  systemd.services.vaultwarden.unitConfig.RequiresMountsFor = [ "/var/lib/vaultwarden" ];
}
