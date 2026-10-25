"""订阅处理：拉取机场订阅、解析 trojan 分享链接、按地区给节点分组。

"""
from base64 import b64decode
from urllib.parse import urlsplit, parse_qs, unquote
from urllib.request import urlopen, Request

# 部分机场会按 UA 返回不同格式，伪装成浏览器以拿到 base64 分享链接列表
USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

# 地区分组：节点名包含关键字即归入该组（按顺序匹配，先匹配到的优先）
CATEGORIES = {
  "hmt": ["香港", "澳门", "台湾"],
  "asia": ["日本", "新加坡"],
  "americas": ["美国"],
}


def fetch(url):
  """下载订阅内容（base64 编码的分享链接列表）。"""
  return urlopen(Request(url, headers={'User-Agent': USER_AGENT}), timeout=30).read()


def parse(content):
  """把订阅内容解析成节点列表。

  目前机场只提供 trojan 节点；遇到其他协议直接报错，避免静默丢节点。
  分享链接格式：trojan://<password>@<server>:<port>?sni=...#<节点名>
  """
  nodes = []
  for link in b64decode(content).decode('utf-8').splitlines():
    url = urlsplit(link)
    if url.scheme != 'trojan':
      raise NotImplementedError(f"unknown protocol: {url.scheme}")
    params = parse_qs(url.query)
    nodes.append({
      'protocol': url.scheme,
      'name': unquote(url.fragment),  # 节点名（含 emoji 和中文），同时作为 outbound tag
      'server': url.hostname,
      'port': url.port,
      'password': url.username,
      'sni': params.get('sni', [None])[0],
    })
  return nodes


def classify(nodes):
  """按 CATEGORIES 给节点分组，返回 {组名: [节点]}。

  额外的两个组：others（没匹配上任何地区）、all（全部节点）。
  注意："套餐到期日期" 这类信息节点也会进入 all/others，和原来的行为一致。
  """
  results = {key: [] for key in CATEGORIES}
  results["others"] = []
  results["all"] = nodes
  for node in nodes:
    cat = next((c for c, kws in CATEGORIES.items() if any(k in node['name'] for k in kws)), "others")
    results[cat].append(node)
  return results
