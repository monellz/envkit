# 网络：eth0 是校园网上行，eth1 是网线直连笔记本的应急通道。由 systemd-networkd 管理。
{ ... }:

let
  # 按 MAC 固定网卡名，不依赖内核探测顺序
  eth0Mac = "e4:5f:01:d9:72:ff"; # 板载网卡（bcmgenet）
  eth1Mac = "c8:a3:62:0e:e8:5f"; # USB 网卡（cdc_ncm）

  # 校园网 DNS；DHCP 下发的 DNS 一律不用
  campusDns = [ "166.111.8.28" "166.111.8.29" "101.7.8.9" ];
in
{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.nameservers = campusDns;
  services.resolved.enable = false;

  systemd.network = {
    enable = true;

    links = {
      "10-eth0" = {
        matchConfig.PermanentMACAddress = eth0Mac;
        linkConfig.Name = "eth0";
      };
      "10-eth1" = {
        matchConfig.PermanentMACAddress = eth1Mac;
        linkConfig.Name = "eth1";
      };
    };

    # Docker 和 sing-box 自己管理的路由和策略规则，networkd 不要清理
    config.networkConfig = {
      ManageForeignRoutes = false;
      ManageForeignRoutingPolicyRules = false;
    };

    networks = {
      # 校园网上行。DHCP 身份标识必须和原系统一致，才能继续拿到固定的
      # 166.111.238.16 / 2402:f000:4:1007:809:ffff:fffc:156f
      "10-eth0" = {
        matchConfig.Name = "eth0";
        linkConfig = {
          RequiredForOnline = "routable";
          RequiredFamilyForOnline = "ipv4";
        };
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          LinkLocalAddressing = "ipv6";
        };
        dhcpV4Config = {
          ClientIdentifier = "mac";
          # 网络里有一台配置错误的 DHCP 服务器，会下发 192.168.31.0/24 的地址
          DenyList = [ "192.168.31.1" ];
          RouteMetric = 101;
          UseDNS = false;
          UseHostname = false;
        };
        dhcpV6Config = {
          DUIDType = "link-layer-time";
          DUIDRawData = "00:01:30:e0:ba:65:e4:5f:01:d9:72:ff";
          IAID = 31027967;
          UseDNS = false;
        };
        ipv6AcceptRAConfig = {
          UseDNS = false;
          RouteMetric = 101;
        };
      };

      # 网线直连笔记本：只分配地址（192.168.0.51–150），不下发网关和 DNS，
      # 笔记本照常用自己的其他网络上网
      "20-eth1" = {
        matchConfig.Name = "eth1";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "no";
          DHCPServer = true;
          IPv6AcceptRA = false;
          LinkLocalAddressing = "ipv6";
          ConfigureWithoutCarrier = true;
        };
        dhcpServerConfig = {
          PoolOffset = 51;
          PoolSize = 100;
          DefaultLeaseTimeSec = "12h";
          MaxLeaseTimeSec = "12h";
          EmitRouter = false;
          EmitDNS = false;
          EmitNTP = false;
          EmitSIP = false;
          EmitPOP3 = false;
          EmitSMTP = false;
          EmitLPR = false;
          EmitTimezone = false;
        };
        addresses = [
          {
            Address = "192.168.0.50/24";
            AddPrefixRoute = false;
          }
        ];
        routes = [
          {
            Destination = "192.168.0.0/24";
            Scope = "link";
            PreferredSource = "192.168.0.50";
          }
        ];
      };
    };
  };

  # 防火墙：只放行 ssh；eth1（直连笔记本）视为可信（tailscale0 见 tailscale.nix）。
  # sing-box 的 auto_redirect 和 Docker 会另外写 nftables 规则，这里不干涉它们
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 3333 ];
    trustedInterfaces = [ "eth1" ];
  };
}
