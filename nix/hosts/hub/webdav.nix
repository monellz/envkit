# WebDAV（Zotero 附件、浏览器书签同步）：rclone serve webdav，只监听 127.0.0.1，
# 经 tailscale serve 的 /dav 对 tailnet 提供（--baseurl /dav：rclone 自己处理前缀，serve 转发时保留前缀）。
# 数据目录 /var/lib/webdav 是数据盘的 bind mount（见 data.nix）。
# 账号在 secrets/hub.yaml 的 webdav/htpasswd（htpasswd 格式，bcrypt），新密码用 `htpasswd -nbB zrx <密码>` 生成。
{ config, pkgs, ... }:

let
  dataDir = "/var/lib/webdav";
in
{
  users.users.webdav = {
    isSystemUser = true;
    group = "webdav";
  };
  users.groups.webdav = { };

  sops.secrets."webdav/htpasswd" = {
    owner = "webdav";
    restartUnits = [ "webdav.service" ];
  };

  systemd.services.webdav = {
    description = "WebDAV server (rclone)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    unitConfig.RequiresMountsFor = [ dataDir ];
    serviceConfig = {
      ExecStart = builtins.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone serve webdav ${dataDir}"
        "--addr 127.0.0.1:8084"
        "--baseurl /dav"
        "--htpasswd ${config.sops.secrets."webdav/htpasswd".path}"
        # 不需要 rclone 的远端配置文件
        "--config /dev/null"
      ];
      User = "webdav";
      Group = "webdav";
      Restart = "on-failure";
      # 只能写数据目录，看不到其他用户的文件
      ProtectSystem = "strict";
      ReadWritePaths = [ dataDir ];
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
