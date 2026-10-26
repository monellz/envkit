"""把机场订阅转换成 sing-box 的节点出站和分组，写进 sops 加密的 secrets 文件。

sing-box 配置的其余部分由 Nix 声明（nix/lib/sing-box.nix）；只有节点和按节点划分的分组
（节点名要拉取订阅后才知道）由这里生成，存为 secrets 中的 sing-box/outbounds，
在激活时由 sops-nix 填进配置模板。

订阅内容来源（任选其一，默认从 sops 中的订阅链接拉取）：
  --url URL     从指定链接拉取
  --file PATH   直接解析已有的订阅内容（base64 编码的分享链接列表）；PATH 为 - 时读标准输入
  --stored      用 sops 中保存的上一次订阅内容，不联网（只修改了分组规则时使用）

在 nix/ 目录下运行，需要能解密 secrets 文件的 age 密钥（~/.config/sops/age/keys.txt）：
  nix run .#sing-box-update-nodes -- [--url URL | --file PATH | --stored] [--dry-run]
"""
import argparse
import json
import subprocess
import sys
from base64 import b64decode
from urllib.parse import urlsplit, parse_qs, unquote
from urllib.request import urlopen, Request

# 部分机场会按 UA 返回不同格式，伪装成浏览器以拿到 base64 分享链接列表
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
)

# 地区分组：节点名包含关键字即归入该组（按顺序匹配，先匹配到的优先）
REGIONS = {
    "hmt": ["香港", "澳门", "台湾"],
    "asia": ["日本", "新加坡"],
    "americas": ["美国"],
}


def is_fixed_ip(name):
    """固定出口 IP 用的节点（新加坡 01）：部分 AI 服务对出口 IP 变化敏感。"""
    return "新加坡" in name and "01" in name


def sops(secrets_file, *args, input_text=None):
    return subprocess.run(
        ["sops", *args, secrets_file], input=input_text, capture_output=True, text=True, check=True,
    ).stdout


def sops_get(secrets_file, key):
    return sops(secrets_file, "--decrypt", "--extract", f'["sing-box"]["{key}"]')


def sops_set(secrets_file, key, value):
    subprocess.run(
        ["sops", "set", secrets_file, f'["sing-box"]["{key}"]', json.dumps(value)], check=True,
    )


def fetch(url):
    return urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=30).read().decode()


def parse(content):
    """把订阅内容解析成节点列表。

    目前机场只提供 trojan 节点；遇到其他协议直接报错，避免静默丢节点。
    分享链接格式：trojan://<password>@<server>:<port>?sni=...#<节点名>
    """
    nodes = []
    for link in b64decode(content.strip()).decode().splitlines():
        if not link.strip():
            continue
        url = urlsplit(link)
        if url.scheme != "trojan":
            raise SystemExit(f"不支持的协议：{url.scheme}")
        params = parse_qs(url.query)
        nodes.append({
            "name": unquote(url.fragment),
            "server": url.hostname,
            "port": url.port,
            "password": unquote(url.username),
            "sni": params.get("sni", [None])[0],
        })
    return nodes


def build_outbounds(nodes):
    """节点出站 + 按节点划分的分组。分组里引用的 direct 出站由 Nix 声明的静态部分提供。

    分组：
      proxy                通用海外出口，默认 fastest（全部节点测速最快）
      proxy-ai             AI 关键域名专用，只能选固定 IP 或亚洲节点，故意不含 direct
      fastest / fastest_in_<地区>  按地区测速
      fixed_ip             固定出口 IP（新加坡 01）
      proxy_by_<地区>      按地区的手动选择器，保留 direct 以便临时直连
    """
    names = [n["name"] for n in nodes]
    by_region = {r: [n["name"] for n in nodes if any(k in n["name"] for k in kws)] for r, kws in REGIONS.items()}
    # 节点只归入第一个匹配的地区
    seen = set()
    for r in REGIONS:
        by_region[r] = [x for x in by_region[r] if not (x in seen or seen.add(x))]
    fixed = [x for x in names if is_fixed_ip(x)]

    groups = [
        {"tag": "proxy", "type": "selector", "outbounds": ["direct", "fastest"] + names, "default": "fastest"},
        {"tag": "proxy-ai", "type": "selector", "outbounds": ["fixed_ip", "fastest_in_asia"], "default": "fixed_ip"},
        {"tag": "fastest", "type": "urltest", "outbounds": names},
        {"tag": "fastest_in_hmt", "type": "urltest", "outbounds": by_region["hmt"]},
        {"tag": "fastest_in_asia", "type": "urltest", "outbounds": by_region["asia"]},
        {"tag": "fastest_in_americas", "type": "urltest", "outbounds": by_region["americas"]},
        {"tag": "fixed_ip", "type": "selector", "outbounds": fixed},
        {"tag": "proxy_by_hmt", "type": "selector", "outbounds": ["direct", "fastest_in_hmt"], "default": "fastest_in_hmt"},
        {"tag": "proxy_by_asia", "type": "selector", "outbounds": ["direct", "fixed_ip", "fastest_in_asia"], "default": "fixed_ip"},
        {"tag": "proxy_by_americas", "type": "selector", "outbounds": ["direct", "fastest_in_americas"],
         "default": "fastest_in_americas"},
    ]
    # 机场改了节点名可能让某个分组变空，空的 selector/urltest 会导致 sing-box 无法启动
    for g in groups:
        if not g["outbounds"]:
            raise SystemExit(f"分组 {g['tag']} 为空，检查节点名或分组规则")

    node_outbounds = [{
        "tag": n["name"],
        "type": "trojan",
        "server": n["server"],
        "server_port": n["port"],
        "password": n["password"],
        "tls": {
            "enabled": True,
            "server_name": n["sni"],
            "insecure": True,  # 机场节点的证书不一定有效
        },
    } for n in nodes]
    return groups + node_outbounds


def main():
    p = argparse.ArgumentParser(description="把机场订阅转换成 sing-box 节点出站，写进 sops secrets")
    src = p.add_mutually_exclusive_group()
    src.add_argument("--url", help="从指定链接拉取订阅")
    src.add_argument("--file", help="直接解析订阅内容文件；- 表示标准输入")
    src.add_argument("--stored", action="store_true", help="用 secrets 中保存的上一次订阅内容，不联网")
    p.add_argument("--secrets", default="secrets/hub.yaml", help="sops 加密的 secrets 文件")
    p.add_argument("--dry-run", action="store_true", help="只解析和分组，不写入 secrets")
    args = p.parse_args()

    if args.stored:
        content = sops_get(args.secrets, "subscription")
    elif args.file:
        content = sys.stdin.read() if args.file == "-" else open(args.file).read()
    else:
        content = fetch(args.url or sops_get(args.secrets, "subscription-url").strip())

    nodes = parse(content)
    if not nodes:
        raise SystemExit("订阅中没有节点")
    outbounds = build_outbounds(nodes)

    for g in outbounds:
        if g["type"] in ("selector", "urltest"):
            print(f"  {g['tag']:<22} {len(g['outbounds'])} 个成员")
    print(f"共 {len(nodes)} 个节点")
    if args.dry_run:
        return

    # 存成 JSON 数组去掉首尾方括号的片段：Nix 侧的配置模板把它拼接进 outbounds 数组
    sops_set(args.secrets, "outbounds", json.dumps(outbounds, ensure_ascii=False)[1:-1])
    if not args.stored:
        sops_set(args.secrets, "subscription", content)
    print(f"已写入 {args.secrets}：sing-box/outbounds" + ("" if args.stored else "、sing-box/subscription"))


if __name__ == "__main__":
    main()
