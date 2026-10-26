"""client 角色：Mac、Arch PC 等能跑 sing-box TUN 的电脑。

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


def linux_tailnet(config):
  """Linux：sing-box 自己访问 tailnet 时绑定 tailscale0（同 gateway：否则会被 auto_detect_interface 绑到物理网卡）。"""
  config["outbounds"].append({
    "tag": "tailnet-direct",
    "type": "direct",
    "bind_interface": "tailscale0",
    # 出站解析域名默认用 dns-cn，.ts.net 必须交给 MagicDNS
    "domain_resolver": "dns-tailnet",
  })
  config["dns"]["servers"].append(
    {"tag": "dns-tailnet", "type": "udp", "server": "100.100.100.100", "detour": "tailnet-direct"})
  return "tailnet-direct"


def macos_tailnet(config):
  """macOS：sing-box 自己访问 tailnet 时，经内置的 tailscale endpoint。

  auto_detect_interface 会把 direct 出站绑到 en0，
  连 100.66.22.71 报 no route to host，访问 100.100.100.100 超时；
  而 Tailscale App 的网卡是 utunN，编号不固定，没法写死 bind_interface。
  所以 sing-box 自己作为一个 tailnet 节点（hostname macbook-sb）。
  注意：只有 sing-box 自己发起的 tailnet 连接（hub 出站、.ts.net DNS、经 7890 访问 .ts.net）走它；
  普通 App 直连 tailnet 地址时，TUN 不接管 100.64/10，仍由 Tailscale App 处理。
  首次启动时 sing-box 日志里会打印登录链接；状态保存在工作目录（-D）下的 tailscale/。
  """
  config["endpoints"] = [{
    "type": "tailscale",
    "tag": "tailscale",
    "hostname": "macbook-sb",
    "state_directory": "tailscale",
  }]
  config["dns"]["servers"].append({"tag": "dns-tailnet", "type": "tailscale", "endpoint": "tailscale"})
  return "tailscale"


def build(nodes, secrets, platform):
  assert platform in ("macos", "linux"), platform
  # 规则集经代理下载：客户端所在网络不固定，直连 ghfast 不一定通
  config = common.base_config(secrets, rule_set_via="proxy")
  common.add_nodes(config, nodes)

  config["inbounds"] = [
    tun_inbound(platform),
    # 本机代理端口：给命令行程序显式指定代理（.zshrc 的 proxy()），兼容原来 ssh -L 的用法
    common.local_in(),
    # 给 ssh -R 转发到别人服务器用：127.0.0.1:9870，只能访问公网和飞连内网域名
    common.ssh_forward_inbound(),
  ]

  # tailnet 出口：Linux 是绑定 tailscale0 的 direct，macOS 是内置 tailscale endpoint
  tailnet = linux_tailnet(config) if platform == "linux" else macos_tailnet(config)
  # 飞连流量经 tailnet 交给 hub
  config["outbounds"].append(common.hub_outbound(secrets, detour=tailnet))

  # DNS：.ts.net 交给 MagicDNS；飞连域名返回 fakeip
  config["dns"]["rules"].insert(0, {"rule_set": "tailnet-domain", "server": "dns-tailnet"})
  common.corp_fakeip_dns(config)

  config["route"]["rules"] = common.head_route_rules() + common.ssh_forward_rules("hub") + [
    # AI 关键域名优先，保证一定走海外
    common.ai_critical_rule(),
    # Tailscale 控制服务器 / DERP 直连，tailnet 不依赖机场
    {"rule_set": "tailscale-control", "outbound": "direct"},
    # tailnet 域名和地址走 Tailscale
    {"rule_set": "tailnet", "outbound": tailnet},
    # 飞连内网域名交给 hub（fakeip 会在这里被还原成域名）
    {"domain": common.CORP_DOMAIN, "domain_suffix": common.CORP_DOMAIN_SUFFIX, "outbound": "hub"},
  ] + common.common_route_rules()

  return config
