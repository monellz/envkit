# 按 digest 固定基础镜像（arm64）。更新：nix run nixpkgs#nix-prefetch-docker -- --image-name overvenus/corplink --image-tag latest --arch arm64 --os linux
{ dockerTools }:

dockerTools.pullImage {
  imageName = "overvenus/corplink";
  imageDigest = "sha256:04f0c1fea937f1f83d996bf002d2ea0201338cea115c9f2cd41229eb971de06a";
  hash = "sha256-8Y7haMKb44ie6vNNpw9mxckP484De2Z/w2x7Jur4Rrk=";
  finalImageName = "overvenus/corplink";
  finalImageTag = "latest";
  os = "linux";
  arch = "arm64";
}
