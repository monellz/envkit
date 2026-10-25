"""各角色（gateway / client / mobile）共用的配置片段。

配置统一使用 sing-box 1.14 写法，不使用任何已废弃字段（见 gate-plan.md 5.2）：
- DNS server 用 type: udp/https，不再用旧的 address 字段
- 用 route.default_domain_resolver 代替旧的 `outbound: any` DNS 规则
- 用 http_clients + route.default_http_client 代替规则集的 download_detour
"""

# GitHub 在国内访问不稳定，规则集和面板都经 ghfast 镜像下载
GITHUB_PROXY = "https://ghfast.top"

# 远程规则集：tag -> SagerNet 仓库中的路径
REMOTE_RULE_SETS = {
  "geosite-geolocation-!cn": "sing-geosite/rule-set/geosite-geolocation-!cn.srs",
  "geosite-geolocation-cn": "sing-geosite/rule-set/geosite-geolocation-cn.srs",
  "geosite-category-ai-!cn": "sing-geosite/rule-set/geosite-category-ai-!cn.srs",
  "geosite-category-ai-chat-!cn": "sing-geosite/rule-set/geosite-category-ai-chat-!cn.srs",
  "geoip-cn": "sing-geoip/rule-set/geoip-cn.srs",
  "geoip-us": "sing-geoip/rule-set/geoip-us.srs",
}

# AI 关键域名：写成内联规则，不依赖远程规则集是否下载成功，
# 并且路由到不含 direct 的 proxy-ai，保证 pi 上的 Claude Code 一定走海外（gate-plan 5.3）
AI_CRITICAL_DOMAIN_SUFFIX = ["anthropic.com", "claude.ai", "claude.com"]

# 公司（飞连）内网域名
CORP_DOMAIN = ["qcjzai.cn"]
CORP_DOMAIN_SUFFIX = [".qcjzai.cn"]

# tailnet 地址段：IPv4 CGNAT 段 + Tailscale 的 IPv6 段
TAILNET_CIDR = ["100.64.0.0/10", "fd7a:115c:a1e0::/48"]

# hub（gateway 角色所在机器）的 tailnet IP：gateway 上 tailnet-gateway-in 的监听地址，
# 也是 client/mobile 的 hub 出站要连的地址。换机器后要改这里（tailscale ip -4）
HUB_TAILNET_IP = "100.66.22.71"

# fakeip 地址段（client/mobile 上给飞连域名用）
FAKEIP_CIDR = ["198.18.0.0/15", "fc00::/18"]

# 自定义规则集，写成 inline，所有角色共用（gate-plan 4.5）
INLINE_RULE_SETS = [
  # tailnet：MagicDNS 域名和 tailnet 地址，只在 route 规则里用
  {"tag": "tailnet", "type": "inline", "rules": [
    {"domain_suffix": [".ts.net"], "ip_cidr": TAILNET_CIDR},
  ]},
  # tailnet-domain：只含域名，DNS 规则专用。
  # 1.14 把在 DNS 规则里引用含 ip_cidr 的规则集视为已废弃的地址过滤写法，所以和上面分开
  {"tag": "tailnet-domain", "type": "inline", "rules": [
    {"domain_suffix": [".ts.net"]},
  ]},
  # tailscale-control：Tailscale 控制服务器和 DERP 中继，直连，不让 tailnet 依赖机场。
  # 实测（2026-10-25，pi）：controlplane/login/derpN 都能直连；log.tailscale.com 直连超时，
  # 所以只列这几个，其余 tailscale 域名（日志上报、网站）按普通规则走代理
  {"tag": "tailscale-control", "type": "inline", "rules": [
    {"domain": ["controlplane.tailscale.com", "login.tailscale.com"],
     "domain_regex": [r"^derp\d+[a-z]?\.tailscale\.com$"]},
  ]},
]


def rule_set_url(tag, mirror=True):
  """远程规则集的下载地址。mirror=True 时经 ghfast 镜像（直连下载用），否则直接用 GitHub 地址（经代理下载用）。"""
  url = f"https://raw.githubusercontent.com/SagerNet/{REMOTE_RULE_SETS[tag]}"
  return f"{GITHUB_PROXY}/{url}" if mirror else url


def base_config(secrets, rule_set_via="direct"):
  """返回公共骨架：日志、clash API、DNS、出站分组、规则集。

  入站、角色特有的出站和路由规则由各角色在 build() 里补充。

  rule_set_via：远程规则集怎么下载。
    "direct"：直连 ghfast 镜像。hub 用这个，并配合 initial_path 本地文件兜底。
    "proxy"：经机场节点直接从 GitHub 下载。client/mobile 用这个：它们所在的网络不固定，
      实测（2026-10-25）Mac 在家用网络下直连 ghfast.top 超时，而首次启动时规则集下载失败会导致 sing-box 起不来。
  """
  assert rule_set_via in ("direct", "proxy"), rule_set_via
  return {
    "log": {"level": "info", "timestamp": True},
    "experimental": {
      # clash API：供 yacd 等面板查看连接、切换节点。只监听本机，并且必须设置 secret，
      # 否则任何能连到 127.0.0.1 的程序都可以把模式切成 direct
      "clash_api": {
        "external_controller": "127.0.0.1:9090",
        "external_ui": "",
        "external_ui_download_url": f"{GITHUB_PROXY}/https://github.com/MetaCubeX/Yacd-meta/archive/gh-pages.zip",
        "external_ui_download_detour": "direct",
        "default_mode": "rule",
        "secret": secrets["CLASH_API_SECRET"],
        "access_control_allow_origin": ["http://127.0.0.1", "http://yacd.haishan.me"],
      },
      # cache.db：保存规则集缓存和 selector 的选择（路径相对 -D 指定的工作目录）
      "cache_file": {"enabled": True},
    },
    "dns": {
      "servers": [
        # 国内 DNS（阿里），也是默认 DNS；不写 detour 即直连
        {"tag": "dns-cn", "type": "udp", "server": "223.5.5.5"},
        # 海外 DNS（Cloudflare DoH），经代理查询，避免污染
        {"tag": "dns-overseas", "type": "https", "server": "1.1.1.1", "detour": "proxy"},
      ],
      "rules": [
        {"clash_mode": "direct", "server": "dns-cn"},
        {"clash_mode": "global", "server": "dns-overseas"},
        {"rule_set": "geosite-geolocation-!cn", "server": "dns-overseas"},
      ],
      "strategy": "prefer_ipv4",  # 同时有 v4/v6 地址时优先用 v4
      "final": "dns-cn",  # 没匹配到任何规则时用国内 DNS
    },
    # 下载远程规则集用的 HTTP 客户端（替代旧的 download_detour）：
    # http-direct 不设 detour 即直连；http-proxy 经 proxy 分组（机场节点）
    "http_clients": [
      {"tag": "http-direct"} if rule_set_via == "direct" else {"tag": "http-proxy", "detour": "proxy"},
    ],
    # 出站分组（节点由 add_nodes() 填充）：
    # - proxy：通用海外出口，默认 fastest（全部节点测速最快）
    # - proxy-ai：AI 关键域名专用，只能选 fixed_ip 或亚洲节点，故意不含 direct
    # - fastest_in_*：按地区测速
    # - fixed_ip：固定出口 IP（新加坡 01），部分 AI 服务对 IP 变化敏感
    # - proxy_by_*：按地区的手动选择器，保留 direct 选项以便临时直连
    "outbounds": [
      {"tag": "proxy", "type": "selector", "outbounds": ["direct", "fastest"], "default": "fastest"},
      {"tag": "proxy-ai", "type": "selector", "outbounds": ["fixed_ip", "fastest_in_asia"], "default": "fixed_ip"},
      {"tag": "fastest", "type": "urltest", "outbounds": []},
      {"tag": "fastest_in_hmt", "type": "urltest", "outbounds": []},
      {"tag": "fastest_in_asia", "type": "urltest", "outbounds": []},
      {"tag": "fastest_in_americas", "type": "urltest", "outbounds": []},
      {"tag": "fixed_ip", "type": "selector", "outbounds": []},
      {"tag": "proxy_by_hmt", "type": "selector", "outbounds": ["direct", "fastest_in_hmt"], "default": "fastest_in_hmt"},
      {"tag": "proxy_by_asia", "type": "selector", "outbounds": ["direct", "fixed_ip", "fastest_in_asia"], "default": "fixed_ip"},
      {"tag": "proxy_by_americas", "type": "selector", "outbounds": ["direct", "fastest_in_americas"], "default": "fastest_in_americas"},
      {"tag": "direct", "type": "direct"},
    ],
    "route": {
      # 出站自动绑定默认网卡（防止 TUN 开启后出站流量又绕回 TUN）
      "auto_detect_interface": True,
      # 出站连接需要解析域名时（例如机场节点的域名）用国内 DNS；替代旧的 `outbound: any` DNS 规则
      "default_domain_resolver": "dns-cn",
      "default_http_client": f"http-{rule_set_via}",
      # 所有规则都没匹配上时直连
      "final": "direct",
      "rules": [],
      "rule_set": INLINE_RULE_SETS + [
        {"tag": tag, "type": "remote", "format": "binary", "url": rule_set_url(tag, mirror=rule_set_via == "direct")}
        for tag in REMOTE_RULE_SETS
      ],
    },
  }


def find_outbound(config, tag):
  for o in config["outbounds"]:
    if o["tag"] == tag:
      return o
  raise KeyError(f"outbound tag not found: {tag}")


def add_nodes(config, nodes):
  """把订阅节点加成 trojan 出站，并填进各分组。"""
  for node in nodes["all"]:
    config["outbounds"].append({
      "tag": node["name"],
      "type": "trojan",
      "server": node["server"],
      "server_port": node["port"],
      "password": node["password"],
      "tls": {
        "enabled": True,
        "server_name": node["sni"],
        "insecure": True,  # 避免 tls 证书问题 # FIXME: 安全性?
      },
    })
    find_outbound(config, "proxy")["outbounds"].append(node["name"])
    find_outbound(config, "fastest")["outbounds"].append(node["name"])
    if "新加坡" in node["name"] and "01" in node["name"]:
      find_outbound(config, "fixed_ip")["outbounds"].append(node["name"])

  for cat in ("hmt", "asia", "americas"):
    for node in nodes[cat]:
      find_outbound(config, f"fastest_in_{cat}")["outbounds"].append(node["name"])

  # 机场改了节点名可能让某个分组变空，而空的 selector/urltest 会导致 sing-box 无法启动，
  # 所以在生成阶段就报错，不让这种配置被发布
  for o in config["outbounds"]:
    if o["type"] in ("selector", "urltest"):
      assert o["outbounds"], f"outbound group {o['tag']} is empty"


def head_route_rules():
  """所有角色路由规则的开头。"""
  return [
    # 嗅探协议和域名（TLS SNI / HTTP Host），写入元数据后继续匹配后面的规则
    {"action": "sniff"},
    # DNS 请求交给 sing-box 的 DNS 模块处理
    {"protocol": "dns", "action": "hijack-dns"},
  ]


def ai_critical_rule():
  """AI 关键域名 -> proxy-ai。放在 clash_mode 和远程规则集之前。"""
  return {"domain_suffix": AI_CRITICAL_DOMAIN_SUFFIX, "outbound": "proxy-ai"}


def ssh_forward_inbound():
  """ssh-forward-in：专门给 `ssh -R` 转发到别人服务器用的入站（gate-plan 4.2）。

  端口和服务器上的转发端口一致，都是 9870：ssh config 里写 `RemoteForward 9870 127.0.0.1:9870`，
  服务器上用 http://127.0.0.1:9870 作为代理（7890/7891 是 Clash 类软件的默认端口，容易冲突）。
  暂不加认证（2026-10-25 决定）：共享服务器上的其他用户也能用它访问公网，
  但访问范围由 ssh_forward_rules() 限制为只能访问公网，碰不到飞连、本机端口和 tailnet。
  """
  return {
    "type": "mixed",
    "tag": "ssh-forward-in",
    "listen": "127.0.0.1",
    "listen_port": 9870,
  }


def ssh_forward_rules():
  """ssh-forward-in 的访问限制：别人的服务器只能访问公网（gate-plan 5.3 第 3 条）。

  必须放在路由规则最前面（sniff / hijack-dns 之后）。
  """
  return [
    # 1. 飞连内网域名直接拒绝
    {"inbound": "ssh-forward-in", "domain": CORP_DOMAIN, "domain_suffix": CORP_DOMAIN_SUFFIX, "action": "reject"},
    # 2. 先把域名解析成 IP。否则对域名目标，后面的 IP 规则不会生效，
    #    用一个解析到 127.0.0.1 的域名（如 localtest.me）就能绕过限制
    {"inbound": "ssh-forward-in", "action": "resolve"},
    # 3. 拒绝私有地址、本机、tailnet 和 fakeip：
    #    挡住 127.0.0.1 上的 corplink socks(1088)、clash API(9090)、vault 等，以及局域网和 tailnet 设备。
    #    0.0.0.0/8 和 :: 在 Linux 上连接时等同于本机，也要拒绝
    {"inbound": "ssh-forward-in", "ip_is_private": True, "action": "reject"},
    {"inbound": "ssh-forward-in",
     "ip_cidr": ["0.0.0.0/8", "127.0.0.0/8", "::/128", "::1/128"] + TAILNET_CIDR + FAKEIP_CIDR,
     "action": "reject"},
  ]


def common_route_rules():
  """按地域分流的公共规则，接在各角色特有规则之后（顺序和旧配置一致）。"""
  return [
    # 局域网 / 本机地址直连
    {"ip_is_private": True, "outbound": "direct"},
    # clash 面板切换的全局直连 / 全局代理模式
    {"clash_mode": "direct", "outbound": "direct"},
    {"clash_mode": "global", "outbound": "proxy"},
    # 国内网站直连
    {"rule_set": "geosite-geolocation-cn", "outbound": "direct"},
    # 海外 AI 服务走亚洲节点（默认固定 IP）
    {"rule_set": "geosite-category-ai-!cn", "outbound": "proxy_by_asia"},
    {"rule_set": "geosite-category-ai-chat-!cn", "outbound": "proxy_by_asia"},
    # 其他海外网站走代理
    {"rule_set": "geosite-geolocation-!cn", "outbound": "proxy"},
  ]


def hub_outbound(secrets, detour=None):
  """hub：client/mobile 经 tailnet 把飞连流量交给 hub 的 tailnet-gateway-in（gate-plan 4.3）。

  detour：Linux 上是 tailnet-direct（绑定 tailscale0），mobile 上是 tailscale endpoint。
  """
  outbound = {
    "tag": "hub",
    "type": "http",
    "server": HUB_TAILNET_IP,
    "server_port": 7890,
    "username": secrets["TAILNET_GATEWAY_USER"],
    "password": secrets["TAILNET_GATEWAY_PASSWORD"],
  }
  if detour:
    outbound["detour"] = detour
  return outbound


def corp_fakeip_dns(config):
  """client/mobile 上的飞连域名：本地不做真实解析，返回 fakeip，把域名原样交给 hub（gate-plan 4.4）。

  飞连内网域名可能只有在公司内网 DNS 里才有记录，本地解析会失败或拿到错误地址；
  用 fakeip 后，TUN 收到连接时能从 fakeip 还原出域名，再按域名路由到 hub。
  """
  config["dns"]["servers"].append(
    {"tag": "dns-fakeip", "type": "fakeip", "inet4_range": FAKEIP_CIDR[0], "inet6_range": FAKEIP_CIDR[1]})
  # 放在 tailnet-domain 之后、clash_mode 之前；只有 A/AAAA 查询返回 fakeip
  config["dns"]["rules"].insert(1, {
    "domain": CORP_DOMAIN, "domain_suffix": CORP_DOMAIN_SUFFIX,
    "query_type": ["A", "AAAA"], "server": "dns-fakeip",
  })
  # fakeip 和域名的对应关系存进 cache.db，重启后已有连接的 fakeip 仍能还原
  config["experimental"]["cache_file"]["store_fakeip"] = True


def local_in():
  """本机代理端口（mixed = http + socks5），给命令行程序显式指定代理用。"""
  return {"type": "mixed", "tag": "local-in", "listen": "127.0.0.1", "listen_port": 7890}
