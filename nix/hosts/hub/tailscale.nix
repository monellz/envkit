# Tailscale：hub 在 tailnet 中的节点，以及对 tailnet 提供的 Web / TCP 服务（tailscale serve）。
#
# 节点身份（名字 hub、地址 100.66.22.71、*.ts.net 证书）全部保存在 /var/lib/tailscale/tailscaled.state；
# 换系统时把这个文件原样拷过来即可保持身份，不需要重新登录。
{ config, lib, pkgs, ... }:

let
  tailscale = config.services.tailscale.package;

  # 对 tailnet 提供的 HTTPS 路径（https://hub.<tailnet>.ts.net/<路径>）。
  # --set-path=/x 转发到 http://127.0.0.1:端口 时，后端收到的路径会去掉 /x；
  # 后端要求保留前缀（应用自己把路由挂在 /x 下）时，在目标地址末尾写上 /x 把前缀加回来。
  webRoutes = {
    "/" = "http://127.0.0.1:8700"; # agents-hub
    "/gitea" = "http://127.0.0.1:8083"; # gitea 路由在根路径，ROOT_URL 的 /gitea/ 只用于生成链接
    "/vault" = "http://127.0.0.1:8082/vault"; # vaultwarden 的路由挂在 /vault 下
    "/dav" = "http://127.0.0.1:8084/dav"; # rclone serve webdav --baseurl /dav
  };

  # 对 tailnet 开放的 TCP 端口
  tcpRoutes = {
    "10022" = "tcp://127.0.0.1:10022"; # gitea 内置 ssh（git remote 用 ssh 别名 gitea）
  };

  applyServe = pkgs.writeShellScript "tailscale-serve-apply" ''
    set -eu
    # 等 tailscaled 登录完成，否则 serve 命令会失败
    for _ in $(seq 1 60); do
      ${tailscale}/bin/tailscale status --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null && break
      sleep 2
    done
    # 先清空再按声明重建：这样从配置里删掉的路径也会被撤销
    ${tailscale}/bin/tailscale serve reset
    ${lib.concatStrings (lib.mapAttrsToList (path: target: ''
      ${tailscale}/bin/tailscale serve --bg --set-path=${lib.escapeShellArg path} ${lib.escapeShellArg target} >/dev/null
    '') webRoutes)}
    ${lib.concatStrings (lib.mapAttrsToList (port: target: ''
      ${tailscale}/bin/tailscale serve --bg --tcp=${port} ${lib.escapeShellArg target} >/dev/null
    '') tcpRoutes)}
  '';
in
{
  services.tailscale = {
    enable = true;
    # 稳定分支的版本比原系统旧；状态文件由新版本写出，用旧版本读取有风险，所以用 unstable 的包
    package = pkgs.unstable.tailscale;
    # 放行 WireGuard 的 UDP 端口，便于和其他设备直连（不经过 DERP 中继）
    openFirewall = true;
    # 不接管系统 DNS：hub 固定用校园网 DNS，.ts.net 由 sing-box 交给 MagicDNS 解析
    extraSetFlags = [ "--accept-dns=false" ];
  };

  # tailnet 内的设备可以访问 hub 上的所有端口（sing-box 的 tailnet-gateway-in 监听 100.66.22.71:7890）
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  systemd.services.tailscale-serve = {
    description = "Apply tailscale serve routes";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    # 路由变化时重新执行（脚本内容随路由变化，所以路径就是触发条件）
    restartTriggers = [ applyServe ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = applyServe;
    };
  };
}
