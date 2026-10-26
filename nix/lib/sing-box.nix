# sing-box 配置（Nix 属性集）：各角色共用同一套规则，按角色组合。
#
#   gateway       hub：TUN 透明代理本机流量，提供 7890 / 9870 / tailnet 网关入口，飞连流量交给 corplink
#   client-macos  Mac：海外直连机场，飞连经 tailnet 交给 hub；sing-box 自己的 tailnet 连接走内置 tailscale endpoint
#   client-linux  Linux 电脑：同上，tailnet 连接绑定 tailscale0
#   mobile        Android SFA：内置 tailscale endpoint 替代 Tailscale App（同一时间只能运行一个 VPN）
#
# 密钥不进入 Nix store：调用方通过 secrets 传入占位符（sops-nix 的 placeholder，激活时替换成真实值）。
# 节点和按节点划分的分组（proxy、proxy-ai、fastest*、fixed_ip、proxy_by_*）同样是密钥，
# 由 sing-box-update-nodes 生成后存进 sops；这里在 outbounds 末尾放一个标记 nodesMarker，
# 渲染模板时把它替换成节点 JSON 片段（见 toTemplate）。
#
# 配置统一使用 sing-box 1.14 写法，不使用已废弃字段：DNS server 用 type 字段，
# route.default_domain_resolver 代替 `outbound: any` DNS 规则，http_clients 代替规则集的 download_detour。
{ lib }:

let
  # hub 在 tailnet 中的地址：tailnet-gateway-in 的监听地址，也是客户端 hub 出站的目标
  hubTailnetIp = "100.66.22.71";

  # tailnet 地址段：IPv4 CGNAT 段 + Tailscale 的 IPv6 段
  tailnetCidr = [ "100.64.0.0/10" "fd7a:115c:a1e0::/48" ];
  # fakeip 地址段（客户端给飞连域名用）
  fakeipCidr = [ "198.18.0.0/15" "fc00::/18" ];

  # 公司（飞连）内网域名
  corpDomain = [ "qcjzai.cn" ];
  corpDomainSuffix = [ ".qcjzai.cn" ];

  # AI 关键域名：写成内联规则，不依赖远程规则集是否下载成功，
  # 并且路由到不含 direct 的 proxy-ai，保证 Claude Code 等一定走海外
  aiCriticalDomainSuffix = [ "anthropic.com" "claude.ai" "claude.com" ];

  # GitHub 在国内访问不稳定：网关直连时经 ghfast 镜像下载规则集
  githubProxy = "https://ghfast.top";

  # 远程规则集：tag -> SagerNet 仓库中的路径（tag 列表和 pkgs/sing-box-rule-sets.nix 一致）
  remoteRuleSets = {
    "geosite-geolocation-!cn" = "sing-geosite/rule-set/geosite-geolocation-!cn.srs";
    "geosite-geolocation-cn" = "sing-geosite/rule-set/geosite-geolocation-cn.srs";
    "geosite-category-ai-!cn" = "sing-geosite/rule-set/geosite-category-ai-!cn.srs";
    "geosite-category-ai-chat-!cn" = "sing-geosite/rule-set/geosite-category-ai-chat-!cn.srs";
    "geoip-cn" = "sing-geoip/rule-set/geoip-cn.srs";
    "geoip-us" = "sing-geoip/rule-set/geoip-us.srs";
  };

  # 自定义规则集，写成 inline
  inlineRuleSets = [
    # tailnet：MagicDNS 域名和 tailnet 地址，只在 route 规则里用
    {
      tag = "tailnet";
      type = "inline";
      rules = [{ domain_suffix = [ ".ts.net" ]; ip_cidr = tailnetCidr; }];
    }
    # tailnet-domain：只含域名，DNS 规则专用（在 DNS 规则里引用含 ip_cidr 的规则集属于已废弃的地址过滤写法）
    {
      tag = "tailnet-domain";
      type = "inline";
      rules = [{ domain_suffix = [ ".ts.net" ]; }];
    }
    # tailscale-control：Tailscale 控制服务器和 DERP 中继，直连，不让 tailnet 依赖机场。
    # 只列 controlplane/login/derpN：它们在国内能直连；log.tailscale.com 等直连不通，按普通规则走代理
    {
      tag = "tailscale-control";
      type = "inline";
      rules = [{
        domain = [ "controlplane.tailscale.com" "login.tailscale.com" ];
        domain_regex = [ "^derp\\d+[a-z]?\\.tailscale\\.com$" ];
      }];
    }
  ];

  # 节点出站在模板中的位置标记
  nodesMarker = "@SING_BOX_NODES@";

  # ---------------------------------------------------------------- 公共部分

  # ruleSetVia：远程规则集怎么下载。
  #   "direct"：直连 ghfast 镜像（网关），配合 ruleSetDir 中的本地文件做首次启动兜底
  #   "proxy"：经机场节点直接从 GitHub 下载（客户端：所在网络不固定，直连 ghfast 不一定通，
  #            而首次启动时规则集下载失败会导致 sing-box 起不来）
  base = { secrets, ruleSetVia, ruleSetDir ? null }: {
    log = { level = "info"; timestamp = true; };
    experimental = {
      # clash API：供 yacd 等面板查看连接、切换节点。只监听本机，并且必须设置 secret，
      # 否则任何能连到 127.0.0.1 的程序都可以把模式切成 direct
      clash_api = {
        external_controller = "127.0.0.1:9090";
        default_mode = "rule";
        secret = secrets.clashApiSecret;
        access_control_allow_origin = [ "http://127.0.0.1" "http://yacd.haishan.me" ];
      };
      # cache.db：规则集缓存和 selector 的选择（路径相对 -D 指定的工作目录）
      cache_file.enabled = true;
    };
    dns = {
      servers = [
        # 国内 DNS（阿里），也是默认 DNS；不写 detour 即直连
        { tag = "dns-cn"; type = "udp"; server = "223.5.5.5"; }
        # 海外 DNS（Cloudflare DoH），经代理查询，避免污染
        { tag = "dns-overseas"; type = "https"; server = "1.1.1.1"; detour = "proxy"; }
      ];
      rules = [
        { clash_mode = "direct"; server = "dns-cn"; }
        { clash_mode = "global"; server = "dns-overseas"; }
        { rule_set = "geosite-geolocation-!cn"; server = "dns-overseas"; }
      ];
      strategy = "prefer_ipv4";
      final = "dns-cn";
    };
    # 下载远程规则集用的 HTTP 客户端：不设 detour 即直连；http-proxy 经 proxy 分组
    http_clients = [
      (if ruleSetVia == "direct" then { tag = "http-direct"; } else { tag = "http-proxy"; detour = "proxy"; })
    ];
    # 节点和分组由 nodesMarker 处的 JSON 片段补齐（分组里会引用 direct）
    outbounds = [ { tag = "direct"; type = "direct"; } ];
    route = {
      # 出站自动绑定默认网卡（防止 TUN 开启后出站流量又绕回 TUN）
      auto_detect_interface = true;
      # 出站连接解析域名（例如机场节点的域名）用国内 DNS
      default_domain_resolver = "dns-cn";
      default_http_client = "http-${ruleSetVia}";
      final = "direct";
      rule_set = inlineRuleSets ++ lib.mapAttrsToList (tag: path: {
        inherit tag;
        type = "remote";
        format = "binary";
        url =
          let url = "https://raw.githubusercontent.com/SagerNet/${path}";
          in if ruleSetVia == "direct" then "${githubProxy}/${url}" else url;
      } // lib.optionalAttrs (ruleSetDir != null) {
        # 首次启动（cache.db 为空）时从本地文件加载
        initial_path = "${ruleSetDir}/${tag}.srs";
      }) remoteRuleSets;
    };
  };

  headRules = [
    # 嗅探协议和域名（TLS SNI / HTTP Host），写入元数据后继续匹配后面的规则
    { action = "sniff"; }
    # DNS 请求交给 sing-box 的 DNS 模块处理
    { protocol = "dns"; action = "hijack-dns"; }
  ];

  aiCriticalRule = { domain_suffix = aiCriticalDomainSuffix; outbound = "proxy-ai"; };

  # 按地域分流的公共规则，接在各角色特有规则之后
  regionRules = [
    { ip_is_private = true; outbound = "direct"; }
    { clash_mode = "direct"; outbound = "direct"; }
    { clash_mode = "global"; outbound = "proxy"; }
    { rule_set = "geosite-geolocation-cn"; outbound = "direct"; }
    { rule_set = "geosite-category-ai-!cn"; outbound = "proxy_by_asia"; }
    { rule_set = "geosite-category-ai-chat-!cn"; outbound = "proxy_by_asia"; }
    { rule_set = "geosite-geolocation-!cn"; outbound = "proxy"; }
  ];

  corpRule = outbound: { domain = corpDomain; domain_suffix = corpDomainSuffix; inherit outbound; };

  # 本机代理端口（mixed = http + socks5），给命令行程序显式指定代理用
  localIn = { type = "mixed"; tag = "local-in"; listen = "127.0.0.1"; listen_port = 7890; };

  # ssh-forward-in：给 `ssh -R` 转发到别人服务器用的入站。端口和服务器上的转发端口一致（9870），
  # ssh config 写 `RemoteForward 9870 127.0.0.1:9870`，服务器上用 http://127.0.0.1:9870 作为代理。
  # 不加认证：共享服务器上的其他用户也能用，访问范围由 sshForwardRules 限制为公网和飞连内网域名
  sshForwardIn = { type = "mixed"; tag = "ssh-forward-in"; listen = "127.0.0.1"; listen_port = 9870; };

  # ssh-forward-in 的访问限制，必须放在路由规则最前面（sniff / hijack-dns 之后）。
  # corpOutbound：本角色访问飞连内网的出站（网关是 corplink，客户端是 hub）。
  # WARN: 9870 没有认证，放行飞连域名后，共享服务器上的任何用户都能经由这个转发访问飞连内网。
  # 这是临时放开；长期应改成带认证的独立入站，或恢复对飞连域名的 reject
  sshForwardRules = corpOutbound: [
    # 飞连内网域名按域名直接交给飞连出站，不进入后面的解析和 IP 限制（飞连域名解析出来多是私有地址，
    # 会被下面拒绝）。只放行域名、不放行内网 IP，所以直接用 IP 访问飞连内网仍会被拒绝
    { inbound = "ssh-forward-in"; domain = corpDomain; domain_suffix = corpDomainSuffix; outbound = corpOutbound; }
    # 先把域名解析成 IP：否则对域名目标，后面的 IP 规则不会生效，
    # 用一个解析到 127.0.0.1 的域名（如 localtest.me）就能绕过限制
    { inbound = "ssh-forward-in"; action = "resolve"; }
    # 拒绝私有地址、本机、tailnet 和 fakeip：挡住本机的 corplink socks、clash API 等，以及局域网和 tailnet 设备。
    # 0.0.0.0/8 和 :: 在 Linux 上连接时等同于本机
    { inbound = "ssh-forward-in"; ip_is_private = true; action = "reject"; }
    {
      inbound = "ssh-forward-in";
      ip_cidr = [ "0.0.0.0/8" "127.0.0.0/8" "::/128" "::1/128" ] ++ tailnetCidr ++ fakeipCidr;
      action = "reject";
    }
  ];

  # 客户端经 tailnet 把飞连流量交给 hub 的 tailnet-gateway-in
  hubOutbound = secrets: detour: {
    tag = "hub";
    type = "http";
    server = hubTailnetIp;
    server_port = 7890;
    username = secrets.tailnetGatewayUser;
    password = secrets.tailnetGatewayPassword;
    inherit detour;
  };

  # 客户端上的飞连域名：本地不做真实解析，返回 fakeip，把域名原样交给 hub。
  # 飞连内网域名可能只有公司内网 DNS 才能解析；用 fakeip 后，TUN 收到连接时能还原出域名再路由到 hub
  corpFakeipDns = {
    server = { tag = "dns-fakeip"; type = "fakeip"; inet4_range = lib.elemAt fakeipCidr 0; inet6_range = lib.elemAt fakeipCidr 1; };
    rule = { domain = corpDomain; domain_suffix = corpDomainSuffix; query_type = [ "A" "AAAA" ]; server = "dns-fakeip"; };
  };

  # 客户端 TUN 网卡地址：不能和 fakeip、docker 网桥（172.17+）、常见局域网重叠；
  # 同时带 IPv6，否则 IPv6 流量会绕过 TUN 直连
  clientTunAddress = [ "10.255.255.253/30" "fdfe:dcba:9876::1/126" ];

  # ---------------------------------------------------------------- 角色

  gateway = { secrets, ruleSetDir }:
    let b = base { inherit secrets ruleSetDir; ruleSetVia = "direct"; };
    in lib.recursiveUpdate b {
      inbounds = [
        # TUN：透明代理本机（以及 docker 容器）的流量
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "sing-box-tun";
          address = [ "198.18.0.1/16" ];
          auto_route = true;
          # Linux 上用 nftables 重定向 TCP，性能更好
          auto_redirect = true;
          # auth-thu 以 uid 61001 运行：校园网认证、DNS、健康检查都不能进 TUN，否则认证失败会导致整台机器断网
          exclude_uid = [ 61001 ];
          # eth1：网线直连的应急通道；tailscale0：tailnet 流量不进 TUN
          exclude_interface = [ "eth1" "tailscale0" ];
          route_exclude_address = tailnetCidr;
          # strict_route 会导致 ping www.baidu.com 不通
          strict_route = false;
          stack = "system";
          # 默认的 hijack 会用 nftables 把所有 53 端口重定向到 sing-box，可能影响 auth-thu 的校园网 DNS
          dns_mode = "disabled";
        }
        # 本机代理端口：hub 上的 Claude Code（http_proxy）用它
        localIn
        # 给 ssh -R 转发到别人服务器用：公网和飞连内网域名（WARN: 无认证，见 sshForwardRules）
        sshForwardIn
        # 给其他 tailnet 设备用的代理入口，主要用于访问飞连内网。只监听 tailnet IP，公网访问不到；
        # 开机时 tailscaled 可能还没起来，依赖 net.ipv4.ip_nonlocal_bind=1
        {
          type = "mixed";
          tag = "tailnet-gateway-in";
          listen = hubTailnetIp;
          listen_port = 7890;
          users = [{ username = secrets.tailnetGatewayUser; password = secrets.tailnetGatewayPassword; }];
        }
      ];
      outbounds = b.outbounds ++ [
        # 飞连内网出口：corplink 容器的 socks5 端口
        { tag = "corplink"; type = "socks"; server = "127.0.0.1"; server_port = 1088; version = "5"; network = "tcp"; }
        # tailnet 出口：必须绑定 tailscale0（普通 direct 会被 auto_detect_interface 绑到 eth0，
        # 而 tailscale serve 只监听在 tailscale0 上）；出站解析域名默认用 dns-cn，.ts.net 要交给 MagicDNS
        { tag = "tailnet-direct"; type = "direct"; bind_interface = "tailscale0"; domain_resolver = "dns-tailnet"; }
      ];
      dns = {
        servers = b.dns.servers ++ [
          { tag = "dns-tailnet"; type = "udp"; server = "100.100.100.100"; detour = "tailnet-direct"; }
        ];
        rules = [{ rule_set = "tailnet-domain"; server = "dns-tailnet"; }] ++ b.dns.rules;
      };
      route.rules = headRules ++ sshForwardRules "corplink" ++ [
        aiCriticalRule
        { rule_set = "tailscale-control"; outbound = "direct"; }
        { rule_set = "tailnet"; outbound = "tailnet-direct"; }
        # 飞连认证域名须直连，避免再次送回飞连
        { domain = [ "feilian.qcjzai.cn" ]; outbound = "direct"; }
        (corpRule "corplink")
      ] ++ regionRules;
    };

  client = { secrets, platform }:
    let
      b = base { inherit secrets; ruleSetVia = "proxy"; };
      linux = platform == "linux";
      # tailnet 出口：Linux 绑定 tailscale0；macOS 的 Tailscale 网卡是 utunN（编号不固定），
      # direct 出站又会被 auto_detect_interface 绑到 en0 而连不上 100.x，
      # 所以 sing-box 自己作为 tailnet 节点（内置 tailscale endpoint，hostname macbook-sb）。
      # 只有 sing-box 自己发起的 tailnet 连接走它，普通 App 访问 tailnet 仍由 Tailscale App 处理
      tailnet = if linux then "tailnet-direct" else "tailscale";
    in
    lib.recursiveUpdate b ({
      inbounds = [
        ({
          type = "tun";
          tag = "tun-in";
          address = clientTunAddress;
          auto_route = true;
          # tailnet 地址段交给系统路由（Tailscale 自己的网卡），不进 TUN
          route_exclude_address = tailnetCidr;
          strict_route = false;
          stack = "system";
        } // lib.optionalAttrs linux {
          interface_name = "sing-box-tun";
          auto_redirect = true;
          exclude_interface = [ "tailscale0" ];
        })
        localIn
        sshForwardIn
      ];
      outbounds = b.outbounds
        ++ lib.optional linux { tag = "tailnet-direct"; type = "direct"; bind_interface = "tailscale0"; domain_resolver = "dns-tailnet"; }
        ++ [ (hubOutbound secrets tailnet) ];
      dns = {
        servers = b.dns.servers ++ [
          (if linux
           then { tag = "dns-tailnet"; type = "udp"; server = "100.100.100.100"; detour = "tailnet-direct"; }
           else { tag = "dns-tailnet"; type = "tailscale"; endpoint = "tailscale"; })
          corpFakeipDns.server
        ];
        rules = [ { rule_set = "tailnet-domain"; server = "dns-tailnet"; } corpFakeipDns.rule ] ++ b.dns.rules;
      };
      # fakeip 和域名的对应关系存进 cache.db，重启后已有连接的 fakeip 仍能还原
      experimental.cache_file.store_fakeip = true;
      route.rules = headRules ++ sshForwardRules "hub" ++ [
        aiCriticalRule
        { rule_set = "tailscale-control"; outbound = "direct"; }
        { rule_set = "tailnet"; outbound = tailnet; }
        (corpRule "hub")
      ] ++ regionRules;
    } // lib.optionalAttrs (!linux) {
      # 首次启动时 sing-box 日志里会打印登录链接；状态保存在工作目录（-D）下的 tailscale/
      endpoints = [{ type = "tailscale"; tag = "tailscale"; hostname = "macbook-sb"; state_directory = "tailscale"; }];
    });

  mobile = { secrets }:
    let b = base { inherit secrets; ruleSetVia = "proxy"; };
    in lib.recursiveUpdate b {
      inbounds = [{
        type = "tun";
        tag = "tun-in";
        address = clientTunAddress;
        auto_route = true;
        # tailnet 流量也要进 TUN，再交给 tailscale endpoint，所以不排除 tailnet 地址段
        strict_route = true;
        stack = "mixed";
      }];
      # 内置的 Tailscale 节点（替代 Tailscale App）。首次启动时 SFA 日志里会打印登录链接
      endpoints = [{ type = "tailscale"; tag = "tailscale"; hostname = "phone"; state_directory = "tailscale"; }];
      outbounds = b.outbounds ++ [ (hubOutbound secrets "tailscale") ];
      dns = {
        servers = b.dns.servers ++ [
          { tag = "dns-tailnet"; type = "tailscale"; endpoint = "tailscale"; }
          corpFakeipDns.server
        ];
        rules = [ { rule_set = "tailnet-domain"; server = "dns-tailnet"; } corpFakeipDns.rule ] ++ b.dns.rules;
      };
      experimental.cache_file.store_fakeip = true;
      route.rules = headRules ++ [
        aiCriticalRule
        { rule_set = "tailscale-control"; outbound = "direct"; }
        { rule_set = "tailnet"; outbound = "tailscale"; }
        (corpRule "hub")
      ] ++ regionRules;
    };

  # 角色名 -> 生成函数（参数：secrets，网关另需 ruleSetDir）
  roles = {
    gateway = gateway;
    client-macos = args: client (args // { platform = "macos"; });
    client-linux = args: client (args // { platform = "linux"; });
    mobile = mobile;
  };
in
{
  inherit roles nodesMarker hubTailnetIp;

  # 生成配置模板文本：outbounds 末尾放 nodesMarker，再把 "nodesMarker"（带引号的 JSON 字符串）
  # 替换成 nodes（节点 JSON 片段，或它的 sops 占位符），得到合法的 JSON
  toTemplate = { role, secrets, nodes, ruleSetDir ? null }:
    let
      cfg = roles.${role} ({ inherit secrets; } // lib.optionalAttrs (role == "gateway") { inherit ruleSetDir; });
      withMarker = cfg // { outbounds = cfg.outbounds ++ [ nodesMarker ]; };
    in
    lib.replaceStrings [ (builtins.toJSON nodesMarker) ] [ nodes ] (builtins.toJSON withMarker);
}
