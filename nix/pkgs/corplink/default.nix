# 飞连（corplink）容器镜像，用 Nix 构建，不需要 Dockerfile。
#
# 基础镜像 overvenus/corplink：Ubuntu + 飞连官方 Linux 客户端（corplink-service，闭源）
# + supervisord 管理的 privoxy（8118，http）、socks5（1080）和修 DNS / MTU 的辅助脚本。
# 飞连会自己建 VPN 隧道、改路由、DNS 和 iptables，所以放在容器里，和 hub 的网络隔离；
# hub 只通过映射到 127.0.0.1 的 socks / http 端口使用它。
#
# 在基础镜像之上加一层：
#   - corplink-headless：无界面登录驱动，从源码构建并打补丁（scan-login-url.patch）
#   - /opt/corplink-dist：corplink-service 和 corplink-headless 的副本。
#     飞连的登录状态和程序都在 /opt/Corplink 下，运行时把宿主机的持久化目录挂到 /opt/Corplink，
#     镜像里原本的程序会被挡住，所以启动时从这里把程序拷进去（见下方 entrypoint）
#   - curl：健康检查用
{ dockerTools, runCommand, writeShellScript, pkgsStatic, corplink-base-image, corplink-service, corplink-headless }:

let
  entrypoint = writeShellScript "corplink-entrypoint" ''
    # /opt/Corplink 是宿主机挂进来的持久化目录（飞连的登录状态）；每次启动把镜像里的程序拷进去，
    # 这样升级镜像后程序是新的，登录状态保留
    cp -f /opt/corplink-dist/corplink-service /opt/corplink-dist/corplink-headless /opt/Corplink/
    exec /startup.sh
  '';

  layer = runCommand "corplink-layer" { } ''
    mkdir -p $out/opt/corplink-dist $out/usr/local/bin
    cp ${corplink-service}/bin/corplink-service ${corplink-headless}/bin/corplink-headless $out/opt/corplink-dist/
    ln -s ${entrypoint} $out/envkit-entrypoint.sh
    ln -s ${pkgsStatic.curl}/bin/curl $out/usr/local/bin/curl
  '';
in
dockerTools.buildImage {
  name = "corplink";
  tag = "envkit";
  fromImage = corplink-base-image;
  copyToRoot = layer;
  # 环境变量（CONTAINER=1、PATH）沿用基础镜像的；这里覆盖入口和工作目录
  config = {
    Entrypoint = [ "/envkit-entrypoint.sh" ];
    WorkingDir = "/opt/Corplink";
  };
}
