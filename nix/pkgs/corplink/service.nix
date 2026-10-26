# 从基础镜像中取出 corplink-service（闭源，不能单独下载）
{ runCommand, coreutils, corplink-base-image }:

runCommand "corplink-service" { nativeBuildInputs = [ coreutils ]; } ''
  mkdir work
  tar -xf ${corplink-base-image} -C work
  for layer in $(find work -name 'layer.tar' -o -name '*.tar' -path '*blobs*'); do
    tar -xf "$layer" -C work opt/Corplink/corplink-service 2>/dev/null || true
  done
  test -x work/opt/Corplink/corplink-service
  install -Dm755 work/opt/Corplink/corplink-service $out/bin/corplink-service
''
