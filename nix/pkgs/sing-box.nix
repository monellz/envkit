# sing-box：使用官方 release 的 musl 静态二进制，和 Mac 等客户端、官方 Docker 镜像是同一个构建
# （nixpkgs 中的版本落后，且编译标签不同）。升级时同时修改 version 和对应架构的 hash，
# 并保持各设备版本一致：配置里用到的字段需要所有设备都支持。
{ lib, stdenvNoCC, fetchurl }:

let
  version = "1.14.4";
  assets = {
    aarch64-linux = {
      name = "sing-box-${version}-linux-arm64-musl";
      hash = "sha256-uV4l+SHcXhekzxMyckPRF3ZCx+NUJb9TcoYsR3w1n1Y=";
    };
  };
  asset = assets.${stdenvNoCC.hostPlatform.system}
    or (throw "sing-box: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "sing-box";
  inherit version;

  src = fetchurl {
    url = "https://github.com/SagerNet/sing-box/releases/download/v${version}/${asset.name}.tar.gz";
    inherit (asset) hash;
  };

  installPhase = ''
    install -Dm755 sing-box $out/bin/sing-box
  '';

  meta = {
    description = "The universal proxy platform";
    homepage = "https://sing-box.sagernet.org";
    license = lib.licenses.gpl3Plus;
    platforms = builtins.attrNames assets;
    mainProgram = "sing-box";
  };
}
