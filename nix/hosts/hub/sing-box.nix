# sing-box 网关：TUN 透明代理本机流量；7890 给本机程序、9870 给 ssh -R 转发、100.66.22.71:7890 给 tailnet 设备。
# 同时渲染发布给客户端（Mac / Linux / 手机）的配置，经 tailscale serve 的 /sing-box 发布。
#
# 配置结构由 lib/sing-box.nix 声明；节点和各入口的密码是密钥，不能进入 Nix store，
# 所以配置写成 sops-nix 模板：激活时把占位符替换成 secrets/hub.yaml 中的值，渲染到 /run/secrets/rendered（内存文件系统）。
# 机场节点的更新：nix run .#sing-box-update-nodes（写入 secrets/hub.yaml 的 sing-box/outbounds），再部署。
#
# hub 上的 Claude Code 经 127.0.0.1:7890 访问 API，sing-box 不可用时会话无法自救：
# 部署前先构建（flake checks 会用假数据跑 sing-box check），切换后检查 claude.ai 的出口
# （curl -x http://127.0.0.1:7890 https://claude.ai/cdn-cgi/trace）。
{ config, lib, pkgs, ... }:

let
  singBox = import ../../lib/sing-box.nix { inherit lib; };
  placeholder = config.sops.placeholder;

  # 模板里的密钥占位符。这些值会被原样嵌进 JSON 字符串，所以不能含有引号或反斜杠
  # （clash API 密钥和 tailnet 网关账号密码都是十六进制随机串）
  secrets = {
    clashApiSecret = placeholder."sing-box/clash-api-secret";
    tailnetGatewayUser = placeholder."sing-box/tailnet-gateway-user";
    tailnetGatewayPassword = placeholder."sing-box/tailnet-gateway-password";
  };

  render = role: singBox.toTemplate {
    inherit role secrets;
    # 节点和分组的 JSON 片段（sing-box-update-nodes 生成）
    nodes = placeholder."sing-box/outbounds";
    # 网关首次启动（cache.db 为空）时从 Nix store 中的本地规则集加载，不依赖下载地址可用
    ruleSetDir = pkgs.sing-box-rule-sets;
  };

  # 发布给客户端的配置：渲染到 /run/secrets/rendered/sing-box-public/，由 tailscale serve 发布
  clientRoles = [ "client-macos" "client-linux" "mobile" ];

  gatewayConfig = config.sops.templates."sing-box/gateway.json".path;
in
{
  sops.secrets = lib.genAttrs [
    "sing-box/outbounds"
    "sing-box/clash-api-secret"
    "sing-box/tailnet-gateway-user"
    "sing-box/tailnet-gateway-password"
  ] (_: { });

  sops.templates = {
    "sing-box/gateway.json" = {
      content = render "gateway";
      # 节点或密码变化后重启 sing-box
      restartUnits = [ "sing-box.service" ];
    };
  } // lib.genAttrs (map (role: "sing-box-public/${role}.json") clientRoles)
    (name: { content = render (lib.removeSuffix ".json" (baseNameOf name)); });

  systemd.services.sing-box = {
    description = "sing-box gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ (render "gateway") ];
    serviceConfig = {
      # 以 root 运行：创建 TUN、写 nftables（auto_redirect）、绑定 tailscale0 都需要
      ExecStartPre = "${pkgs.sing-box}/bin/sing-box check -c ${gatewayConfig}";
      ExecStart = "${pkgs.sing-box}/bin/sing-box run -c ${gatewayConfig} -D /var/lib/sing-box";
      # /var/lib/sing-box：cache.db（规则集缓存、selector 的选择）
      StateDirectory = "sing-box";
      StateDirectoryMode = "0700";
      Restart = "always";
      RestartSec = 5;
      LimitNOFILE = 65536;
    };
  };

  # tailnet-gateway-in 监听在 tailnet IP 上。开机时 sing-box 可能比 tailscaled 先启动，这个地址还不存在；
  # 允许绑定非本机地址，避免 sing-box 启动失败
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.ipv6.ip_nonlocal_bind" = 1;
  };

  # TUN 网卡上进来的是本机自己的流量（被 auto_route / auto_redirect 送进来的），不需要防火墙过滤
  networking.firewall.trustedInterfaces = [ "sing-box-tun" ];
}
