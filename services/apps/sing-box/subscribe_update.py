import os
import argparse

def fetch_link(url):
  from urllib.request import urlopen, Request
  req = Request(url, headers={'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'})
  ret = urlopen(req).read()
  return ret

def classify_nodes(nodes):
  categories = {
    "hmt": ["香港", "澳门", "台湾"],
    "asia": ["日本", "新加坡"],
    "americas": ["美国"],
  }
  results = {key: [] for key in categories.keys()}
  results["others"] = []
  results["all"] = nodes
  for node in nodes:
    classified = False
    for cat, keywords in categories.items():
      if any(keyword in node['name'] for keyword in keywords):
        results[cat].append(node)
        classified = True
        break
    if not classified:
        results["others"].append(node)
       
  return results

def parse_link(content):
  from base64 import b64decode
  share_links = b64decode(content).decode('utf-8').splitlines()

  from urllib.parse import urlsplit, parse_qs, unquote
  def base64_padding(s):
    return s + '=' * (-len(s) % 4)

  nodes = []
  for link in share_links:
    url = urlsplit(link)
    protocol = url.scheme
    if protocol == 'trojan':
      print(f"{url=}")
      password = url.username
      server = url.hostname
      port = url.port
      params = parse_qs(url.query)
      peer = params.get('peer', [None])[0]
      sni = params.get('sni', [None])[0]
      allow_insecure = params.get('allowInsecure', [None])[0]
      name = unquote(url.fragment)

      node = {
        'protocol': protocol,
        'name': name,
        'server': server,
        'port': port,
        'password': password,
        'peer': peer,
        'sni': sni,
        'allow_insecure': allow_insecure,
      }
    else:
      raise NotImplementedError(f"unknown protocol: {protocol}, link: {link}")

    nodes.append(node)
  
  return nodes 

def generate_singbox_config(nodes):
  github_proxy_url = "https://ghfast.top"
  config = {
    'log': {
      'level': "debug",
      'timestamp': True,
    },
    'experimental': {
      'clash_api': {
        'external_controller': '127.0.0.1:9090',
        'external_ui': '',
        "external_ui_download_url": f"{github_proxy_url}/https://github.com/MetaCubeX/Yacd-meta/archive/gh-pages.zip",
        'external_ui_download_detour': "direct",
        "default_mode": "rule",
        'secret': '',
        "access_control_allow_origin": [
            "http://127.0.0.1",
            "http://yacd.haishan.me"
        ],
      },
      "cache_file": {
        "enabled": True, # 用于存rule-set的cache
      }
    },
    "dns": {
      "fakeip": { # TODO: 不理解
        "enabled": True,
        "inet4_range": "198.18.0.0/15",
        "inet6_range": "fc00::/18"
      },
      "servers": [
        {
          "tag": "direct_dns",
          "address": "223.5.5.5", # alibaba的dns
          "strategy": "prefer_ipv4", # 如果返回ipv4地址以及ipv6地址，优先使用ipv4地址
          "detour": "direct", # 对应outbounds的tag
        },
        {
          "tag": "cloudflare",
          "address": "https://1.1.1.1/dns-query",
          "strategy": "prefer_ipv4",
          "detour": "proxy",
        }
        # {
        #   "tag": "google",
        #   "address": "https://dns.google/dns-query",
        #   "address_resolver": "default-dns",
        #   "address_strategy": "prefer_ipv4",
        #   "strategy": "prefer_ipv4",
        #   "client_subnet": "1.0.1.0"
        # }
      ],
      "rules": [
        {
          "outbound": "any", # 任何出站流量都使用这个规则 (即来自outbounds的流量，或者说从outboudn来到dns rule匹配的流量)
          "server": "direct_dns",
        },
        {
          "clash_mode": "direct",
          "server": "direct_dns",
        },
        {
          "clash_mode": "global",
          "server": "cloudflare",
        },
        {
          "rule_set": "geosite-geolocation-!cn",
          "server": "cloudflare",
        },
      ],
      "disable_cache": False, # cache/expire是跟dns缓存加速相关的（TODO：确认）
      "disable_expire": False,
      "independent_cache": False,
      "strategy": "prefer_ipv4", # 对于dns解析的默认规则，也就是如果ipv6/ipv4都返回了，用ipv4
      "final": "direct_dns", # 所有rule都匹配失败的去向
    },
    "inbounds": [
      # 对于客户端，直接用tun就好，让几乎所有流量都走经过singbox分发
      {
        "type": "tun",
        "tag": "tun_in",
        "interface_name": "sing-box-tun", # 创建的虚拟网卡名称
        "address": [
          # 虚拟网卡地址
          "198.18.0.1/16",
        ],
        "auto_route": True, # 设置到虚拟网卡到默认路由（TODO：不理解）
        "auto_redirect": True,
        "strict_route": False, # 在启动auto_route时执行严格的路由规则（TODO：不理解）
        # [WARN] strict_route=True会导致ping www.baidu.com不通
        "endpoint_independent_nat": False, # 文档说不需要就不开否则性能会下降（TODO：不理解）
        "stack": "system", # TODO：不理解
      },
      # 需要作为http server来帮其他机器过流量
      # netstat -tuln | grep 7890 检查端口是否打开 
      {
        "type": "http",
        "tag": "http-in",
        "listen": "127.0.0.1",
        "listen_port": 7890,
        "set_system_proxy": False,
      },
    ],
    "outbounds": [
      {
        "tag": "proxy",
        "type": "selector",
        "outbounds": [
          "direct",
          "fastest",
        ],
        "default": "fastest",
      },
      {
        "tag": "fastest",
        "type": "urltest",
        "outbounds": [],
      },
      {
        "tag": "fastest_in_hmt",
        "type": "urltest",
        "outbounds": [],
      },
      {
        "tag": "fastest_in_asia",
        "type": "urltest",
        "outbounds": [],
      },
      {
        "tag": "fastest_in_americas",
        "type": "urltest",
        "outbounds": [],
      },
      {
        "tag": "proxy_by_hmt",
        "type": "selector",
        "outbounds": [
          "direct",
          "fastest_in_hmt",
        ],
        "default": "fastest_in_hmt",
      },
      {
        "tag": "proxy_by_asia",
        "type": "selector",
        "outbounds": [
          "direct",
          "fastest_in_asia",
        ],
        "default": "fastest_in_asia",
      },
      {
        "tag": "proxy_by_americas",
        "type": "selector",
        "outbounds": [
          "direct",
          "fastest_in_americas",
        ],
        "default": "fastest_in_americas",
      },
      {
        "tag": "direct",
        "type": "direct", # 直接出站，不过代理
      },
      # FIXME: 然后添加自己的所有代理节点（并在urltest里面也添加对应的tag）
    ],
    "route": {
      "auto_detect_interface": True,
      "rules": [
        {
          "action": "sniff", # 嗅探协议，写元数据，然后继续往下判断
        },
        {
          "action": "hijack-dns",
          "protocol" : "dns",
        },
        {
            "ip_is_private": True, # 本地链接走direct
            "outbound": "direct",
        },
        {
            "clash_mode": "direct",
            "outbound": "direct"
        },
        {
            "clash_mode": "global",
            "outbound": "proxy"
        },
        {
            "rule_set": "geosite-geolocation-cn",
            "outbound": "direct",
        },
        {
            "rule_set": "geosite-category-ai-!cn",
            "outbound": "proxy_by_asia",
        },
        {
            "rule_set": "geosite-category-ai-chat-!cn",
            "outbound": "proxy_by_asia",
        },
        {
            "rule_set": "geosite-geolocation-!cn",
            "outbound": "proxy",
        },
        {
            "action": "route", # default outbound
            "outbound": "direct",
        }
      ],
      "rule_set": [
        {
          "tag": "geosite-geolocation-!cn",
          "type": "remote",
          "format": "binary",
          "url": f"{github_proxy_url}/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs",
          "download_detour": "direct"
        },
        {
          "tag": "geosite-geolocation-cn",
          "type": "remote",
          "format": "binary",
          "url": f"{github_proxy_url}/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs",
          "download_detour": "direct"
        },
        {
          "tag": "geosite-category-ai-!cn",
          "type": "remote",
          "format": "binary",
          "url": f"{github_proxy_url}/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ai-!cn.srs",
          "download_detour": "direct"
        },
        {
          "tag": "geosite-category-ai-chat-!cn",
          "type": "remote",
          "format": "binary",
          "url": f"{github_proxy_url}/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ai-chat-!cn.srs",
          "download_detour": "direct"
        },
        {
          "tag": "geoip-cn",
          "type": "remote",
          "format": "binary",
          "url": f"{github_proxy_url}/https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
          "download_detour": "direct",
        },
        {
          "tag": "geoip-us",
          "type": "remote",
          "format": "binary",
          "url": f"{github_proxy_url}/https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-us.srs",
          "download_detour": "direct",
        },
      ]
    },
  }
  for node in nodes['all']:
    if node['protocol'] == 'trojan':
      outbound = {
        'tag': node['name'],
        'type': 'trojan',
        'server': node['server'],
        'server_port': node['port'],
        'password': node['password'],
        'tls': {
          'enabled': True,
          'server_name': node['sni'],
          'insecure': True, # 避免tls证书问题 # FIXME: 安全性?
        }
      }
      config['outbounds'].append(outbound)

      # fastest & proxy
      config['outbounds'][0]['outbounds'].append(node['name'])
      config['outbounds'][1]['outbounds'].append(node['name'])
    else:
      raise NotImplementedError(f"unknown protocol: {node['protocol']}")

  # fastest_in_hmt
  for node in nodes['hmt']:
    config['outbounds'][2]['outbounds'].append(node['name'])

  # fastest_in_asia
  for node in nodes['asia']:
    config['outbounds'][3]['outbounds'].append(node['name'])

  # fastest_in_americas
  for node in nodes['americas']:
    config['outbounds'][4]['outbounds'].append(node['name'])
  
  return config

if __name__ == "__main__":
  # ip addr test: https://whatismyipaddress.com/
  parser = argparse.ArgumentParser(description="Update the airport link")
  parser.add_argument("--link", type=str, help="The link to update", default=None)
  parser.add_argument("--content", type=str, help="The content of the link", default=None)
  parser.add_argument("--content_fn", type=str, help="The path to the content file", default="content.bin")
  parser.add_argument("--config_fn", type=str, help="The path to the config file", default="sing-box.json")
  args = parser.parse_args()

  if args.content is not None:
    with open(args.content, 'rb') as f:
        content = f.read()
    print(f"{content=}")
    nodes = parse_link(content)
    nodes = classify_nodes(nodes)
    print(f"{nodes=}")
  elif args.link is not None:
    content = fetch_link(args.link)
    print(f"{content=}")
    nodes = parse_link(content)
    nodes = classify_nodes(nodes)
    print(f"{nodes=}")
  else:
    raise ValueError("Either --link or --content must be provided")
  
  config = generate_singbox_config(nodes)

  import json
  json_str = json.dumps(config, ensure_ascii=False, indent=2)
  print(json_str)

  script_path = os.path.abspath(__file__)
  project_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(script_path))))
  output_dir = os.path.join(project_dir, "services", "apps", "sing-box")
  print(f"{project_dir=}")
  print(f"{output_dir=}")

  if args.link is not None:
    with open(os.path.join(output_dir, "link.txt"), 'w') as f:
      f.write(args.link)
  if args.content_fn is not None:
    with open(os.path.join(output_dir, args.content_fn), 'wb') as f:
      f.write(content)
  if args.config_fn is not None:
    with open(os.path.join(output_dir, args.config_fn), 'w') as f:
      f.write(json_str)
