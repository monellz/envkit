# macOS：sing-box 客户端（gate-plan 阶段 4）

Mac 本机运行官方 sing-box（TUN 模式）：海外流量直连机场，飞连流量经 tailnet 交给 hub，
tailnet 流量交给 Tailscale App。配置由 hub 生成并发布，本机只负责拉取（`scripts/sync_sing_box.sh`）。

### 关于 tailnet 里的 `macbook-sb` 节点

sing-box 把飞连流量转给 hub（100.66.22.71）时需要走 tailnet，但它自己发出的连接都会被绑到 en0，
而 Tailscale App 的网卡是 utunN（编号由系统按创建顺序分配，重启、重连后可能变化），没法写死在配置里。
所以配置里内置了一个 tailscale endpoint：sing-box 进程内自带 WireGuard 和用户态网络栈，
作为 tailnet 节点 `macbook-sb`，自己建立到 hub 的加密隧道，不依赖任何系统网卡。

- 只有 sing-box 自己发起的 tailnet 连接走它（hub 出站、`.ts.net` DNS、经 7890 访问 `.ts.net`）
- 普通 App 直接访问 tailnet 仍由 Tailscale App（`macbook-pro`）处理，TUN 不接管 100.64/10
- 状态（节点密钥）在 `/usr/local/var/lib/sing-box/tailscale/`；在 Tailscale 后台给 `macbook-sb`
  设置 **Disable key expiry**，否则 180 天后需要重新登录

| 部件 | 位置 |
| --- | --- |
| 二进制 | `/usr/local/bin/sing-box`（v1.14.4，和 hub 同版本） |
| 配置 | `/usr/local/etc/sing-box/config.json`（来自 `https://hub.angora-wall.ts.net/sing-box/client-macos.json`） |
| 工作目录 | `/usr/local/var/lib/sing-box`（cache.db） |
| 日志 | `/usr/local/var/log/sing-box.log`、`sing-box-sync.log`（newsyslog 轮转） |
| launchd | `io.sagernet.sing-box`（常驻）、`io.sagernet.sing-box-sync`（每小时同步） |
| 本机端口 | `127.0.0.1:7890`（local-in，无认证）、`127.0.0.1:7891`（ssh-forward-in，带认证） |

## 迁移步骤

### 0. 准备

- Tailscale App 已登录，`tailscale status` 能看到 `hub`
- envkit 仓库已更新到包含本目录的版本
- 找到现在占用 7890 的 `ssh -L`，新的 sing-box 要用这个端口：

  ```bash
  lsof -nP -iTCP:7890 -sTCP:LISTEN
  ```

- 卸载 Homebrew 装的旧版 sing-box（1.10.1）：`brew uninstall sing-box`
- 卸载 SFM 1.10.1：退出 App，删除 `/Applications/SFM.app`；
  `systemextensionsctl list` 里如果还有 `io.nekohasekai.sfavt` 相关的扩展，在「系统设置 → 通用 → 登录项与扩展」中移除

### 1. 安装（不启动，不影响现有网络）

```bash
proxy                                    # 下载 GitHub release 需要代理（此时仍是 ssh -L）
sudo -E bash bootstrap/macos/install_sing_box.sh install [已登录的 tailscale 状态目录]
```

第一次安装时如果不带状态目录，前台试运行时日志会打印 `macbook-sb` 的登录链接，用浏览器批准即可。

### 2. 前台试运行

停掉 `ssh -L`（第 0 步找到的进程），然后：

```bash
sudo sing-box run -c /usr/local/etc/sing-box/config.json -D /usr/local/var/lib/sing-box
```

另开一个终端逐项验证：

```bash
# 海外 / 国内 / Claude 出口
curl -sI https://www.google.com | head -1
curl -sI https://www.baidu.com | head -1
curl -s https://claude.ai/cdn-cgi/trace | grep loc        # 不能是 CN

# 飞连：经 hub（R1：Mac 上的 sing-box 能否连到 100.66.22.71）
curl -sI https://git.qcjzai.cn | head -1                   # 期望 302

# tailnet：MagicDNS 解析（.ts.net 也会进 sing-box）和访问
dscacheutil -q host -a name hub.angora-wall.ts.net
curl -sI https://hub.angora-wall.ts.net/ | head -1
tailscale ping hub

# 7891 只能访问公网
curl -sI -x http://127.0.0.1:7891 https://www.google.com | head -1        # 407
```

前台日志里能直接看到每个连接走了哪个出站。任何一项不通，Ctrl-C 退出即可恢复原状（再重新起 `ssh -L`）。

R1（sing-box 的出站被绑到 en0，连不上 100.x）已在 2026-10-25 预演时确认，并用 `macbook-sb` 解决；
`git.qcjzai.cn` 或 `.ts.net` 不通时，先看日志里 `endpoint/tailscale` 是否在等待登录。

### 2.5 DNS：默认用路由器，`.ts.net` 交给 Tailscale，飞连域名交给 sing-box

2026-10-25 的结论：

- 系统默认 DNS **保持路由器下发的**（不手动设置），需要网页登录的 Wi-Fi 原生可用。
  默认 DNS 可能被污染，但 TLS/HTTP/QUIC 连接会被 sing-box 嗅探出域名、按域名交给代理，实测不受影响
- Tailscale App 默认会接管系统 DNS，关掉：`tailscale set --accept-dns=false`
- 按域名后缀单独指定（由 install 安装）：
  - `/etc/resolver/ts.net` → `100.100.100.100`：`.ts.net` 由 Tailscale 解析，不依赖 sing-box
  - `/etc/resolver/qcjzai.cn` → `10.255.255.254`（sing-box 的 TUN DNS）：飞连域名得到 fakeip。
    必须这样做：git.qcjzai.cn 的公网 IP 上 22 端口不提供 ssh，而 ssh 没有域名可嗅探

验证：

```bash
dscacheutil -q host -a name git.qcjzai.cn            # 198.18.x（fakeip）
dscacheutil -q host -a name hub.angora-wall.ts.net   # 100.66.22.71
(sleep 5) | nc git.qcjzai.cn 22 | head -c 30         # SSH-2.0-OpenSSH...
```

### 3. 启用 launchd

```bash
sudo bash bootstrap/macos/install_sing_box.sh enable
tail -f /usr/local/var/log/sing-box.log
```

### 4. 系统代理：保留，指向本机 sing-box

**保留** HTTP/HTTPS 系统代理 `127.0.0.1:7890`（以前指向 `ssh -L`，现在是本机 sing-box 的 `local-in`）。
TUN 是「失败即放行」的：sing-box 挂掉或重启的几秒内，TUN 网卡消失，新连接会直接从国内发出。
系统代理是「失败即断开」的：遵循系统代理的程序（浏览器、Claude/ChatGPT 桌面版等）在 sing-box 不可用时连接失败，
不会漏到国内；而且代理请求自带域名，不受 DNS 污染影响。两者叠加：遵循系统代理的走 7890，其余由 TUN 接管。

- 系统已有的绕过列表（127.0.0.1、localhost、`*.local`、私有网段）够用；tailnet 没有绕过，经 7890 → `macbook-sb` 也能访问
- 不再需要 `ssh -L 7890`（tmux `feilian` 里的 autossh 不要再启动，否则会和 sing-box 抢 7890）
- `.zshrc` 的 `proxy()` 继续指向 `127.0.0.1:7890`，`alias claude="proxy claude"` 同样是失败即断开

### 5. 回归验证（gate-plan 阶段 4 验证项）

- 浏览器：google、baidu、`git.qcjzai.cn`、`https://hub.angora-wall.ts.net/`
- `git clone` 公司仓库（ssh 和 https）
- 睡眠唤醒、切换 Wi-Fi 后自动恢复；`tailscale ping hub` 能建立直连

## 回滚

```bash
sudo bash bootstrap/macos/install_sing_box.sh disable
# sing-box 异常退出时可能没恢复 DNS 设置，必要时清空：
sudo networksetup -setdnsservers Wi-Fi empty
```

然后恢复 `ssh -L 7890` 和系统代理。

## 更新

- 配置：每小时自动同步；立即同步 `sudo bash scripts/sync_sing_box.sh`
- 版本：改 `install_sing_box.sh` 的 `VERSION` 和 sha256（和 hub 的镜像一起升级），再执行 `install` 和
  `sudo launchctl kickstart -k system/io.sagernet.sing-box`
