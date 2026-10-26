# hub-boot：hub 的启动位管理（说明见 hub-boot.sh）
{ writeShellApplication, coreutils, util-linux, systemd, gnugrep, gnused }:

writeShellApplication {
  name = "hub-boot";
  runtimeInputs = [ coreutils util-linux systemd gnugrep gnused ];
  text = builtins.readFile ./hub-boot.sh;
}
