"""gateway 角色：pi 上运行的 sing-box。

和其他角色相比，gateway 额外负责：
- 校园网认证（auth-thu）流量绕过 TUN
- 飞连（corplink）内网流量交给本机 corplink 容器的 socks 端口
- 首次启动时从本地文件加载规则集，不依赖 ghfast 是否可用
"""
from .. import common

# 容器内路径：compose 把 services/apps/sing-box/live/ 挂载到 /conf
INITIAL_RULE_SET_DIR = "/conf/srs"


def build(nodes, secrets):
  config = common.base_config(secrets)
  common.add_nodes(config, nodes)

  config["inbounds"] = [
    # TUN：透明代理本机（以及 docker 容器）的流量
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "sing-box-tun",
      "address": ["198.18.0.1/16"],  # 虚拟网卡地址
      "auto_route": True,  # 自动把默认路由指向 TUN
      "auto_redirect": True,  # Linux 上用 nftables 重定向 TCP，性能更好
      # auth-thu 容器以 uid 61001 运行：校园网认证、DNS、健康检查都不能进 TUN，
      # 否则认证失败会导致整台 pi 断网（必须和 compose.yml 里的 user 一致）
      "exclude_uid": [61001],
      # eth1：网线直连的应急通道；tailscale0：tailnet 流量不进 TUN
      "exclude_interface": ["eth1", "tailscale0"],
      # tailnet 地址段不走 TUN（IPv4 CGNAT 段 + Tailscale 的 IPv6 段）
      "route_exclude_address": ["100.64.0.0/10", "fd7a:115c:a1e0::/48"],
      "strict_route": False,  # strict_route=True 会导致 ping www.baidu.com 不通
      "stack": "system",
      # 1.14 起默认 hijack：会用 nftables 把所有 53 端口重定向到 sing-box，
      # 不确定是否尊重 exclude_uid（可能影响 auth-thu 的校园网 DNS），所以关掉以保持 1.12 的行为。
      # DNS 仍然会被路由规则里的 hijack-dns 处理。
      "dns_mode": "disabled",
    },
    # 本机代理端口：Claude Code（http_proxy）和 Mac 的 ssh -L 都用它。mixed = http + socks5
    {
      "type": "mixed",
      "tag": "local-in",
      "listen": "127.0.0.1",
      "listen_port": 7890,
    },
  ]

  # 飞连内网出口：corplink 容器的 socks5 端口（映射见 compose.yml）
  config["outbounds"].insert(0, {
    "tag": "corplink",
    "type": "socks",
    "server": "127.0.0.1",
    "server_port": 1088,  # match compose.yml
    "version": "5",
    "network": "tcp",
  })

  config["route"]["rules"] = common.head_route_rules() + [
    # AI 关键域名优先，保证一定走海外
    common.ai_critical_rule(),
    # 飞连认证域名须直连，避免再次送回飞连；无域名的隧道连接由 final direct 处理。
    {"domain": ["feilian.qcjzai.cn"], "outbound": "direct"},
    # 其余公司域名交给飞连
    {"domain": common.CORP_DOMAIN, "domain_suffix": common.CORP_DOMAIN_SUFFIX, "outbound": "corplink"},
  ] + common.common_route_rules()

  # 首次启动（cache.db 为空，例如新建容器）时从本地 srs 文件加载规则集，
  # 避免 ghfast 不可用时 sing-box 启动失败；之后由 sing-box 自己按时更新到 cache.db
  for rs in config["route"]["rule_set"]:
    rs["initial_path"] = f"{INITIAL_RULE_SET_DIR}/{rs['tag']}.srs"

  return config
