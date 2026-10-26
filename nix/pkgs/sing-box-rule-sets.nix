# sing-box 远程规则集的本地副本：网关首次启动（cache.db 为空）时从这里加载，
# 不依赖 ghfast 等下载地址可用；之后由 sing-box 自己定期更新到 cache.db。
# 固定在上游 rule-set 分支的某个 commit，内容不会变，hash 才能长期有效。
# 输出目录里的文件名是 <tag>.srs，和生成器里规则集的 tag 一致（tag 列表见 generator/common.py 的 REMOTE_RULE_SETS）。
{ lib, runCommand, fetchurl }:

let
  geositeRev = "c72a45799f8d0b7f5546e93795d3d75c72c808cc";
  geoipRev = "eb32cd6ed4a16fcb3bf9a36ccebf28e45716ae84";

  ruleSets = {
    "geosite-geolocation-!cn" = { repo = "sing-geosite"; rev = geositeRev; hash = "sha256-UrJKIOiIO50ZYaaXTcXX8spt7gGFpwhK8PA535v2NKE="; };
    "geosite-geolocation-cn" = { repo = "sing-geosite"; rev = geositeRev; hash = "sha256-anlENI4CVrIjQ5uFN5IDRbAVez+xuOt7eGRrUrFMwrE="; };
    "geosite-category-ai-!cn" = { repo = "sing-geosite"; rev = geositeRev; hash = "sha256-viKd+FnnifFkEe+vRE6VEqS0qCH/rdlfsc3F/Cv2DbA="; };
    "geosite-category-ai-chat-!cn" = { repo = "sing-geosite"; rev = geositeRev; hash = "sha256-viKd+FnnifFkEe+vRE6VEqS0qCH/rdlfsc3F/Cv2DbA="; };
    "geoip-cn" = { repo = "sing-geoip"; rev = geoipRev; hash = "sha256-ga2lyv2dgxrcSHdvKc3+VclxPZKHyu753pJe8w9mzOQ="; };
    "geoip-us" = { repo = "sing-geoip"; rev = geoipRev; hash = "sha256-kI2K8CDmzB5iil3N1ajmI76Uef8l5s08OJRuo8d0J1s="; };
  };

  fetchRuleSet = tag: { repo, rev, hash }: fetchurl {
    url = "https://raw.githubusercontent.com/SagerNet/${repo}/${rev}/${tag}.srs";
    # store 路径名不允许出现 "!"
    name = "${lib.replaceStrings [ "!" ] [ "not-" ] tag}.srs";
    inherit hash;
  };
in
runCommand "sing-box-rule-sets" { } ''
  mkdir -p $out
  ${lib.concatStrings (lib.mapAttrsToList (tag: src: ''
    ln -s ${fetchRuleSet tag src} $out/${lib.escapeShellArg "${tag}.srs"}
  '') ruleSets)}
''
