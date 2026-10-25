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
    # 给 ssh -R 转发到别人服务器用：127.0.0.1:9870，只能访问公网
    common.ssh_forward_inbound(),
    # 给其他 tailnet 设备（Mac、手机等）用的代理入口，主要用于访问飞连内网。
    # 只监听 tailnet IP，公网（eth0）访问不到；开机时 tailscaled 可能还没起来，
    # 依赖 sysctl net.ipv4.ip_nonlocal_bind=1（bootstrap/pi4b/etc/sysctl.d/90-nonlocal-bind.conf）
    {
      "type": "mixed",
      "tag": "tailnet-gateway-in",
      "listen": common.HUB_TAILNET_IP,
      "listen_port": 7890,
      "users": [{"username": secrets["TAILNET_GATEWAY_USER"], "password": secrets["TAILNET_GATEWAY_PASSWORD"]}],
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

  # tailnet 出口：必须绑定 tailscale0。
  # 普通 direct 出站会被 auto_detect_interface 绑到 eth0，而 tailscale serve 只监听在 tailscale0 上
  # domain_resolver：出站连接前解析域名用的是 route.default_domain_resolver（dns-cn），不走 DNS 规则，
  # 所以要单独指定 MagicDNS，否则 .ts.net 会被发到 223.5.5.5，返回空结果
  config["outbounds"].append({
    "tag": "tailnet-direct",
    "type": "direct",
    "bind_interface": "tailscale0",
    "domain_resolver": "dns-tailnet",
  })

  # MagicDNS：.ts.net 域名交给 tailscaled 的 100.100.100.100 解析（公共 DNS 解析不了）
  config["dns"]["servers"].append(
    {"tag": "dns-tailnet", "type": "udp", "server": "100.100.100.100", "detour": "tailnet-direct"})
  config["dns"]["rules"].insert(0, {"rule_set": "tailnet-domain", "server": "dns-tailnet"})

  config["route"]["rules"] = common.head_route_rules() + common.ssh_forward_rules() + [
    # AI 关键域名优先，保证一定走海外
    common.ai_critical_rule(),
    # Tailscale 控制服务器 / DERP 直连，tailnet 不依赖机场
    {"rule_set": "tailscale-control", "outbound": "direct"},
    # tailnet 域名和地址走 tailscale0，不能被发到机场节点
    {"rule_set": "tailnet", "outbound": "tailnet-direct"},
    # 飞连认证域名须直连，避免再次送回飞连；无域名的隧道连接由 final direct 处理。
    {"domain": ["feilian.qcjzai.cn"], "outbound": "direct"},
    # 其余公司域名交给飞连
    {"domain": common.CORP_DOMAIN, "domain_suffix": common.CORP_DOMAIN_SUFFIX, "outbound": "corplink"},
  ] + common.common_route_rules()

  # 首次启动（cache.db 为空，例如新建容器）时从本地 srs 文件加载规则集，
  # 避免 ghfast 不可用时 sing-box 启动失败；之后由 sing-box 自己按时更新到 cache.db
  for rs in config["route"]["rule_set"]:
    if rs["type"] != "remote":
      continue
    rs["initial_path"] = f"{INITIAL_RULE_SET_DIR}/{rs['tag']}.srs"

  return config
