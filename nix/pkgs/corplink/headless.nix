# corplink-headless：飞连客户端的无界面登录驱动（开源），从源码构建并打补丁
#（公司的扫码登录地址已更换，见 scan-login-url.patch）
{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule {
  pname = "corplink-headless";
  version = "0-unstable-2026-10-13";
  src = fetchFromGitHub {
    owner = "overvenus";
    repo = "corplink-headless";
    rev = "2e9656729485274bb0162010ce6dfe486dbb4e70";
    hash = "sha256-l/dDCKVkJj2mH72tYIcCIglNs+ZvhSlwmL4/lnXkmPA=";
  };
  vendorHash = "sha256-AvnzJfxVEDLR07+bDNYqiHrRJwbFMAkwwDvLHNvqu7I=";
  patches = [ ./scan-login-url.patch ];
  env.CGO_ENABLED = 0;
  # 只要主程序，不跑上游的测试（需要网络）
  doCheck = false;
  meta.mainProgram = "corplink-headless";
}
