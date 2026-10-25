"""mobile 角色：Android 手机上的 SFA（gate-plan 3、阶段 7）。

Android 同一时间只能运行一个 VPN（P6），所以用 sing-box 内置的 tailscale endpoint
替代 Tailscale App：一个 VPN 同时负责翻墙和 tailnet。
输出：out/public/mobile.json（SFA 远程 profile）
"""
from .. import common

TUN_ADDRESS = ["10.255.255.253/30", "fdfe:dcba:9876::1/126"]


def build(nodes, secrets):
  # 规则集经代理下载：客户端所在网络不固定，直连 ghfast 不一定通
  config = common.base_config(secrets, rule_set_via="proxy")
  common.add_nodes(config, nodes)

  config["inbounds"] = [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": TUN_ADDRESS,
      "auto_route": True,
      # 手机上 tailnet 流量也要进 TUN，再交给 tailscale endpoint，所以不排除 tailnet 地址段
      "strict_route": True,
      "stack": "mixed",
    },
  ]

  # 内置的 Tailscale 节点。首次启动时在 SFA 日志里会打印登录链接，用浏览器打开登录即可，
  # 配置里不写 auth key；状态保存在 SFA 数据目录下的 tailscale/ 里
  config["endpoints"] = [
    {
      "type": "tailscale",
      "tag": "tailscale",
      "hostname": "phone",
      "state_directory": "tailscale",
    },
  ]

  # 飞连流量经 tailnet 交给 hub
  config["outbounds"].append(common.hub_outbound(secrets, detour="tailscale"))

  # DNS：.ts.net 由 endpoint 自带的 MagicDNS 解析；飞连域名返回 fakeip
  config["dns"]["servers"].append({"tag": "dns-tailnet", "type": "tailscale", "endpoint": "tailscale"})
  config["dns"]["rules"].insert(0, {"rule_set": "tailnet-domain", "server": "dns-tailnet"})
  common.corp_fakeip_dns(config)

  config["route"]["rules"] = common.head_route_rules() + [
    # AI 关键域名优先，保证一定走海外
    common.ai_critical_rule(),
    # Tailscale 控制服务器 / DERP 直连（endpoint 自己的流量）
    {"rule_set": "tailscale-control", "outbound": "direct"},
    # tailnet 域名和地址交给内置 tailscale endpoint
    {"rule_set": "tailnet", "outbound": "tailscale"},
    # 飞连内网域名交给 hub
    {"domain": common.CORP_DOMAIN, "domain_suffix": common.CORP_DOMAIN_SUFFIX, "outbound": "hub"},
  ] + common.common_route_rules()

  return config
