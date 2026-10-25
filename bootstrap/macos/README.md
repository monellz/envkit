# macOS：sing-box 客户端（gate-plan 阶段 4）

Mac 本机运行官方 sing-box（TUN 模式）：海外流量直连机场，飞连流量经 tailnet 交给 hub，
tailnet 流量交给 Tailscale App。配置由 hub 生成并发布，本机只负责拉取（`scripts/sync_sing_box.sh`）。

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

- 卸载 SFM 1.10.1：退出 App，删除 `/Applications/SFM.app`；
  `systemextensionsctl list` 里如果还有 `io.nekohasekai.sfavt` 相关的扩展，在「系统设置 → 通用 → 登录项与扩展」中移除

### 1. 安装（不启动，不影响现有网络）

```bash
proxy                                    # 下载 GitHub release 需要代理（此时仍是 ssh -L）
sudo -E bash bootstrap/macos/install_sing_box.sh install
```

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

**R1 的已知风险**：`git.qcjzai.cn` 或 `.ts.net` 不通，并且日志显示 `hub` / `tailnet-direct` 出站连 100.x 超时，
说明 sing-box 的出站被绑到了 en0。这时需要改生成器（client-macos 加 tailscale endpoint 作为 detour），回到 hub 上处理。

### 3. 启用 launchd

```bash
sudo bash bootstrap/macos/install_sing_box.sh enable
tail -f /usr/local/var/log/sing-box.log
```

### 4. 清理旧的代理方式

```bash
# 关闭系统代理（按实际网络服务名，networksetup -listallnetworkservices 查看）
sudo networksetup -setwebproxystate Wi-Fi off
sudo networksetup -setsecurewebproxystate Wi-Fi off
```

- 不再需要 `ssh -L 7890`（如果是开机自启的，一并移除）
- `.zshrc` 的 `proxy()` 继续指向 `127.0.0.1:7890`，现在指向本机 sing-box

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
