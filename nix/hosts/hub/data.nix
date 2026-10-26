# 服务数据放在数据盘（/mnt/disk，2TB USB 移动硬盘）上，bind mount 到各服务模块默认的 /var/lib/<服务>，
# 这样模块按默认路径工作，系统盘重装也不影响数据。
#
# 数据盘没插或挂载失败时：bind mount 也会失败（都带 nofail，不会卡住开机），
# 而依赖这些目录的服务通过 RequiresMountsFor 不会启动——否则服务会在空目录里初始化出一份全新的状态。
{ lib, ... }:

let
  dataDisk = "/mnt/disk";
  # /mnt/disk/<名字> -> /var/lib/<名字>
  dirs = [ "gitea" "vaultwarden" "webdav" ];
in
{
  fileSystems = lib.genAttrs (map (d: "/var/lib/${d}") dirs) (target: {
    device = "${dataDisk}/${baseNameOf target}";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ dataDisk ];
  });
}
