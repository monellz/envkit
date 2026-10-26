# 校园网认证：开机登录并保持在线。
# 以固定 uid 61001 运行：sing-box TUN 的 exclude_uid 靠这个 uid 让认证、DNS 和联网检查都不经过代理，
# 否则认证失败会导致整台机器断网。
{ config, pkgs, ... }:

let
  uid = 61001;
  # 账号密码（{"username": ..., "password": ...}），存在 secrets/hub.yaml 中，开机时解密
  configFile = config.sops.secrets."auth-thu.json".path;
in
{
  sops.secrets."auth-thu.json" = {
    owner = "auth-thu";
    # 账号密码变化后重启认证服务（重启不会下线，见下方说明）
    restartUnits = [ "auth-thu.service" ];
  };

  users.users.auth-thu = {
    isSystemUser = true;
    inherit uid;
    group = "auth-thu";
  };
  users.groups.auth-thu.gid = uid;

  systemd.services.auth-thu = {
    description = "Tsinghua campus network authentication";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # 已在线时 auth 会直接进入保活，不会重复登录；退出时也不会主动下线，
    # 所以重启这个服务（包括 nixos-rebuild switch 时）不会断网。
    # 不在启动前执行 deauth：那会让整台机器短暂掉线。
    serviceConfig = {
      ExecStart = "${pkgs.auth-thu}/bin/auth-thu -c ${configFile} auth -k";
      User = "auth-thu";
      Group = "auth-thu";
      Restart = "always";
      RestartSec = 10;
    };
  };
}
