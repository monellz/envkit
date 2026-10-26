# nix run .#sing-box-update-nodes：把机场订阅转换成 sing-box 节点出站，写进 sops secrets（说明见 update_nodes.py）
{ stdenvNoCC, python3, sops, makeWrapper, lib }:

stdenvNoCC.mkDerivation {
  pname = "sing-box-update-nodes";
  version = "0";
  src = ./update_nodes.py;
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    install -Dm644 $src $out/share/sing-box-update-nodes/update_nodes.py
    makeWrapper ${python3}/bin/python3 $out/bin/sing-box-update-nodes \
      --add-flags $out/share/sing-box-update-nodes/update_nodes.py \
      --prefix PATH : ${lib.makeBinPath [ sops ]}
  '';
  meta.mainProgram = "sing-box-update-nodes";
}
