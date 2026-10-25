"""配置生成器入口。

用法（在 services/apps/sing-box 目录下）：
  python3 -m generator --role gateway                    # 用 secrets/subscription.env 里的订阅链接
  python3 -m generator --role gateway --content content.bin   # 用已保存的订阅内容，不联网拉取
  python3 -m generator --role gateway --fetch-rule-sets  # 同时下载规则集到 out/srs/（供首次启动使用）

生成结果只写到 out/，不会碰正在运行的配置（live/）；切换到线上由 apply.sh 负责。
每个配置都会先用线上同版本的镜像执行 `sing-box check`，通过后才替换 out/ 里的文件。
"""
import argparse
import json
import os
import subprocess
import sys
from urllib.request import urlopen

from . import common, subscription
from .roles import gateway

ROLES = {"gateway": gateway}
APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # services/apps/sing-box
SECRETS_DIR = os.path.join(APP_DIR, "secrets")  # git-crypt 加密
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


def load_nodes(args):
  """获取订阅节点。

  优先级：--content 指定的文件 > 订阅链接（--link 或 SUB_URL）> 上次保存的 content.bin。
  联网拉取成功后会覆盖 content.bin，作为下次离线生成的备份。
  """
  content_fn = os.path.join(APP_DIR, "content.bin")
  link = args.link or load_env(os.path.join(SECRETS_DIR, "subscription.env")).get("SUB_URL")
  if args.content is None and link:
    content = subscription.fetch(link)
    with open(content_fn, "wb") as f:
      f.write(content)
  else:
    with open(args.content or content_fn, "rb") as f:
      content = f.read()
  return subscription.classify(subscription.parse(content))


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
  parser = argparse.ArgumentParser(description="按角色生成 sing-box 配置")
  parser.add_argument("--role", choices=ROLES, action="append", required=True, help="可重复指定多个角色")
  parser.add_argument("--out", default=os.path.join(APP_DIR, "out"))
  parser.add_argument("--link", help="订阅链接（默认读 secrets/subscription.env 中的 SUB_URL）")
  parser.add_argument("--content", help="使用已保存的订阅内容文件，不联网拉取")
  parser.add_argument("--fetch-rule-sets", action="store_true", help="下载远程规则集到 <out>/srs/")
  parser.add_argument("--no-check", action="store_true", help="跳过 sing-box check（仅调试用）")
  args = parser.parse_args()

  secrets = load_env(os.path.join(SECRETS_DIR, "credentials.env"))
  nodes = load_nodes(args)
  os.makedirs(args.out, exist_ok=True)
  if args.fetch_rule_sets:
    fetch_rule_sets(args.out)

  for role in args.role:
    config = ROLES[role].build(nodes, secrets)
    path = os.path.join(args.out, f"{role}.json")
    # 先写临时文件并 check，通过后再原子替换，保证 out/ 里的配置始终是合法的
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
      json.dump(config, f, ensure_ascii=False, indent=2)
    if not args.no_check:
      check(tmp)
    os.replace(tmp, path)
    print(f"wrote {path}")


if __name__ == "__main__":
  sys.exit(main())
