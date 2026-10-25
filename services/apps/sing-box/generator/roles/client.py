"""client 角色：Mac、Arch PC 等能跑 sing-box TUN 的电脑（gate-plan 3、4.1）。

海外流量从本机直连机场，不再绕 hub；只有飞连流量经 tailnet 交给 hub。
macOS 和 Linux 的差异只在 TUN 参数和 tailnet 出口，所以按 platform 生成两份：
  out/public/client-macos.json、out/public/client-linux.json
"""
from .. import common

# TUN 网卡地址：不能和 fakeip（198.18.0.0/15）、docker 网桥（172.17+）、常见局域网重叠。
# 同时带 IPv6，否则校园网 IPv6 流量会绕过 TUN 直连
TUN_ADDRESS = ["10.255.255.253/30", "fdfe:dcba:9876::1/126"]


def tun_inbound(platform):
  tun = {
    "type": "tun",
    "tag": "tun-in",
    "address": TUN_ADDRESS,
    "auto_route": True,
    # tailnet 地址段交给系统路由（Tailscale 自己的网卡），不进 TUN
    "route_exclude_address": common.TAILNET_CIDR,
    "strict_route": False,
    "stack": "system",
    # dns_mode 用 1.14 默认的 hijack：系统 DNS 指向 sing-box，飞连域名才能拿到 fakeip
  }
  if platform == "linux":
    tun["interface_name"] = "sing-box-tun"
    tun["auto_redirect"] = True  # 只有 Linux 支持
    tun["exclude_interface"] = ["tailscale0"]
  # macOS 的 TUN 网卡名由系统分配（utunN），不能指定
  return tun


def tailnet_outbound(platform):
  """tailnet 出口。

  Linux：绑定 tailscale0（同 gateway，P2）。
  macOS：Tailscale 的网卡是 utunN，编号不固定，没法写死 bind_interface；
    先用普通 direct，阶段 4 实测（R1）。如果被 auto_detect_interface 绑到 en0 而连不上，
    改为 tailscale endpoint 作为 detour。
  """
  outbound = {"tag": "tailnet-direct", "type": "direct", "domain_resolver": "dns-tailnet"}
  if platform == "linux":
    outbound["bind_interface"] = "tailscale0"
  return outbound


def build(nodes, secrets, platform):
  assert platform in ("macos", "linux"), platform
  config = common.base_config(secrets)
  common.add_nodes(config, nodes)

  config["inbounds"] = [
    tun_inbound(platform),
    # 本机代理端口：给命令行程序显式指定代理（.zshrc 的 proxy()），兼容原来 ssh -L 的用法
    common.local_in(),
    # 给 ssh -R 转发到别人服务器用：127.0.0.1:7891，带认证，只能访问公网
    common.ssh_forward_inbound(secrets),
  ]

  config["outbounds"].append(tailnet_outbound(platform))
  # 飞连流量经 tailnet 交给 hub；Linux 上强制走 tailscale0
  config["outbounds"].append(common.hub_outbound(secrets, detour="tailnet-direct" if platform == "linux" else None))

  # DNS：.ts.net 交给 MagicDNS；飞连域名返回 fakeip
  config["dns"]["servers"].append(
    {"tag": "dns-tailnet", "type": "udp", "server": "100.100.100.100", "detour": "tailnet-direct"})
  config["dns"]["rules"].insert(0, {"rule_set": "tailnet-domain", "server": "dns-tailnet"})
  common.corp_fakeip_dns(config)

  config["route"]["rules"] = common.head_route_rules() + common.ssh_forward_rules() + [
    # AI 关键域名优先，保证一定走海外
    common.ai_critical_rule(),
    # Tailscale 控制服务器 / DERP 直连，tailnet 不依赖机场（R2）
    {"rule_set": "tailscale-control", "outbound": "direct"},
    # tailnet 域名和地址走 Tailscale
    {"rule_set": "tailnet", "outbound": "tailnet-direct"},
    # 飞连内网域名交给 hub（fakeip 会在这里被还原成域名）
    {"domain": common.CORP_DOMAIN, "domain_suffix": common.CORP_DOMAIN_SUFFIX, "outbound": "hub"},
  ] + common.common_route_rules()

  return config
