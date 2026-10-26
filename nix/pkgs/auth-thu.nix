# 清华校园网认证客户端 GoAuthing（auth-thu）。
# 直接使用上游 release 的静态二进制；升级时同时修改 version 和对应架构的 hash。
{ lib, stdenvNoCC, fetchurl }:

let
  version = "2.4.0";
  assets = {
    aarch64-linux = {
      name = "auth-thu.linux.arm64";
      hash = "sha256-/BcJ58UW3fWoQIpjJVwx2Dx9tiQhTofjcdxH3IWoWZ4=";
    };
  };
  asset = assets.${stdenvNoCC.hostPlatform.system}
    or (throw "auth-thu: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "auth-thu";
  inherit version;

  src = fetchurl {
    url = "https://github.com/z4yx/GoAuthing/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/auth-thu
  '';

  meta = {
    description = "Tsinghua University campus network authentication client";
    homepage = "https://github.com/z4yx/GoAuthing";
    license = lib.licenses.gpl3Only;
    platforms = builtins.attrNames assets;
    mainProgram = "auth-thu";
  };
}
