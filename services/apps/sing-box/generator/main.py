"""配置生成器入口。

用法（在 services/apps/sing-box 目录下）：
  python3 -m generator                       # 用 secrets/subscription.b64 生成全部配置
  python3 -m generator --fetch               # 先按 SUB_URL 拉订阅，覆盖 subscription.b64，再生成
  python3 -m generator --target gateway      # 只生成某一份（可重复指定）
  python3 -m generator --fetch-rule-sets     # 同时下载规则集到 out/srs/（gateway 首次启动用）
日常更新请直接用 ./update.sh。

输出：
  out/gateway.json                 hub 本机用，由 apply.sh 切换上线，不发布
  out/public/client-macos.json     经 tailscale serve 发布给 Mac
  out/public/client-linux.json     发布给 Arch PC 等 Linux 电脑
  out/public/mobile.json           发布给手机（SFA 远程 profile）

每个配置都会先用线上同版本的镜像执行 `sing-box check`，通过后才替换 out/ 里的文件。
"""
import argparse
import json
import os
import subprocess
import sys
from urllib.request import urlopen

from . import common, subscription
from .roles import client, gateway, mobile

# 目标名 -> (相对 out/ 的输出路径, 构建函数)
TARGETS = {
  "gateway": ("gateway.json", lambda n, s: gateway.build(n, s)),
  "client-macos": ("public/client-macos.json", lambda n, s: client.build(n, s, "macos")),
  "client-linux": ("public/client-linux.json", lambda n, s: client.build(n, s, "linux")),
  "mobile": ("public/mobile.json", lambda n, s: mobile.build(n, s)),
}
APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # services/apps/sing-box
SECRETS_DIR = os.path.join(APP_DIR, "secrets")  # git-crypt 加密
# 订阅内容（base64 编码的分享链接列表）。只有 --fetch 时才会联网更新它
SUBSCRIPTION_FILE = os.path.join(SECRETS_DIR, "subscription.b64")
# 必须和 compose.yml 中的镜像版本一致，否则 check 的结果没有意义
IMAGE = os.environ.get("SING_BOX_IMAGE", "ghcr.io/sagernet/sing-box:v1.14.4")


def load_env(path):
  """读取简单的 KEY=VALUE 文件（忽略空行和 # 注释）。"""
  env = {}
  if os.path.exists(path):
    with open(path) as f:
      for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
          k, v = line.split("=", 1)
          env[k.strip()] = v.strip()
  return env


def fetch_subscription(link):
  """拉取订阅；先确认能解析出节点，再覆盖 subscription.b64，避免把错误页面存进去。"""
  content = subscription.fetch(link)
  nodes = subscription.parse(content)
  assert nodes, "subscription contains no nodes"
  with open(SUBSCRIPTION_FILE, "wb") as f:
    f.write(content)
  print(f"fetched subscription: {len(nodes)} nodes -> {SUBSCRIPTION_FILE}")


def fetch_rule_sets(out_dir):
  """下载全部远程规则集到 <out>/srs/，apply.sh 会把它们拷到 live/srs/ 供 initial_path 使用。"""
  srs_dir = os.path.join(out_dir, "srs")
  os.makedirs(srs_dir, exist_ok=True)
  for tag in common.REMOTE_RULE_SETS:
    data = urlopen(common.rule_set_url(tag), timeout=60).read()
    with open(os.path.join(srs_dir, f"{tag}.srs"), "wb") as f:
      f.write(data)
    print(f"fetched {tag}: {len(data)} bytes")


def check(path):
  """用一次性容器执行 sing-box check（--network none，不会影响宿主机网络）。"""
  path = os.path.abspath(path)
  subprocess.run(
    ["docker", "run", "--rm", "--network", "none", "-v", f"{path}:/c.json:ro", IMAGE, "check", "-c", "/c.json"],
    check=True,
  )


def main():
  parser = argparse.ArgumentParser(description="生成各设备的 sing-box 配置")
  parser.add_argument("--target", choices=TARGETS, action="append", help="只生成指定的配置（可重复），默认全部")
  parser.add_argument("--out", default=os.path.join(APP_DIR, "out"))
  parser.add_argument("--fetch", action="store_true", help="先拉取订阅并覆盖 secrets/subscription.b64")
  parser.add_argument("--link", help="订阅链接（默认读 secrets/subscription.env 中的 SUB_URL），配合 --fetch 使用")
  parser.add_argument("--fetch-rule-sets", action="store_true", help="下载远程规则集到 <out>/srs/")
  parser.add_argument("--no-check", action="store_true", help="跳过 sing-box check（仅调试用）")
  args = parser.parse_args()

  if args.fetch:
    link = args.link or load_env(os.path.join(SECRETS_DIR, "subscription.env")).get("SUB_URL")
    if not link:
      sys.exit("没有订阅链接：请在 secrets/subscription.env 中填写 SUB_URL，或用 --link 指定")
    fetch_subscription(link)

  secrets = load_env(os.path.join(SECRETS_DIR, "credentials.env"))
  with open(SUBSCRIPTION_FILE, "rb") as f:
    nodes = subscription.classify(subscription.parse(f.read()))

  if args.fetch_rule_sets:
    fetch_rule_sets(args.out)

  for name in args.target or TARGETS:
    relpath, build = TARGETS[name]
    path = os.path.join(args.out, relpath)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 先写临时文件并 check，通过后再原子替换，保证 out/ 里的配置始终是合法的
    # （out/public 由 tailscale serve 直接发布，客户端随时可能来下载）
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
      json.dump(build(nodes, secrets), f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600)  # 含节点和认证密码；tailscaled 和容器都以 root 读取，不受影响
    if not args.no_check:
      check(tmp)
    os.replace(tmp, path)
    print(f"wrote {path}")


if __name__ == "__main__":
  sys.exit(main())
