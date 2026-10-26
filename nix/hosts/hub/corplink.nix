# 飞连（corplink）：公司内网 VPN。以 OCI 容器运行（podman），镜像由 Nix 构建（pkgs/corplink）。
# 飞连会自己建 VPN 隧道、改路由、DNS 和 iptables，放在容器自己的网络空间里，不影响 hub 的 sing-box / tailscale；
# hub 只经映射到 127.0.0.1 的端口使用它：sing-box 的 corplink 出站连 socks 1088。
#
# 登录状态持久化在 /var/lib/corplink（重建容器、升级镜像都不用重新扫码）：
#   opt/  → /opt/Corplink              .config.json、device.conf、cert/ 等（程序由镜像启动时拷入）
#   etc/  → /usr/local/etc/corplink    udid（设备 ID；变了会被当成一台新设备）
# 首次登录：journalctl -u podman-corplink 中会打印扫码链接，用飞连 App 扫码。
{ pkgs, ... }:

let
  stateDir = "/var/lib/corplink";
in
{
  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers.corplink = {
      # 镜像从 Nix store 加载，不从网络拉取
      image = "corplink:envkit";
      imageFile = pkgs.corplink-image;
      hostname = "ubuntu";
      environment.COMPANY_CODE = "qingcheng";
      ports = [
        "127.0.0.1:1088:1080" # socks5：sing-box 的 corplink 出站
        "127.0.0.1:8888:8118" # http（privoxy）
      ];
      volumes = [
        "${stateDir}/opt:/opt/Corplink"
        "${stateDir}/etc:/usr/local/etc/corplink"
      ];
      extraOptions = [
        # 建 VPN 隧道需要 TUN 设备和改容器内路由 / iptables 的权限（只作用于容器自己的网络空间）
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun"
        "--shm-size=512m"
        # 健康检查：绕开代理、从飞连的隧道网卡访问公司 git，确认 VPN 可用（只用于状态显示，不会自动重启）
        "--health-cmd=curl -fsS --noproxy '*' --interface 'if!utun' --connect-timeout 5 --max-time 10 https://git.qcjzai.cn/ >/dev/null || exit 1"
        "--health-interval=30s"
        "--health-timeout=15s"
        "--health-retries=3"
        "--health-start-period=180s"
      ];
    };
  };

  # 登录状态只有 root 可读
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
    "d ${stateDir}/opt 0700 root root -"
    "d ${stateDir}/etc 0700 root root -"
  ];
}
