# Raspberry Pi 4B

本目录配置当前 Debian 12 / Raspberry Pi OS 的双网口主机。沿用
`bootstrap/arch` 的目录结构和 `scripts/{color,log,func}.sh`；
系统配置复制到 `/etc`，共用的 `copy` 会为修改前的文件创建备份。

## 网络分工

| 部件 | 配置 |
| --- | --- |
| systemd-networkd / eth0 | 校园 DHCPv4、IPv6 RA / DHCPv6；拒绝 DHCPv4 服务器 192.168.31.1 |
| systemd-networkd / eth1 | 静态地址 192.168.0.50/24；DHCP 地址池 192.168.0.51–150，租期 12 小时 |
| networkd DHCP 服务 | 只下发地址、子网掩码和租期，不下发默认网关或 DNS；电脑沿用其他网络上网 |
| /etc/resolv.conf | 显式配置校园 DNS 166.111.8.28、166.111.8.29、101.7.8.9 |
| NetworkManager、dhcpcd、dnsmasq | 停用并 mask |

systemd-networkd 不写 `/etc/resolv.conf`。这里使用固定校园 DNS，未启用
systemd-resolved；与 Arch 笔记本需要随网络切换 DNS 的配置有所不同。
Pi 本机和认证服务使用校园 DNS；直连电脑不从 Pi 获取 DNS 配置。

直连需要两端各有一个地址：Pi 的 eth1 固定为 192.168.0.50，电脑的以太网接口
通过 DHCP 自动取得同网段地址。电脑的 Wi-Fi 地址属于另一个接口，不替代这个地址。

`10-eth0.network` 沿用当前主机的 IPv4 MAC Client ID，以及原 dhcpcd 的
IPv6 DUID/IAID，以保持现有租约身份。迁移时取得的地址仍是
`166.111.238.16` 和 `2402:f000:4:1007:809:ffff:fffc:156f`。
这些身份参数是本机专用，复制到其他设备前需要调整。

仅明确匹配 eth0、eth1；Docker 网桥、veth 和 sing-box TUN 不交给 networkd。
`20-external-routing.conf` 保留 Docker / sing-box 自己添加的路由和策略规则。
eth1 使用显式子网路由，兼容旧配置留下的 noprefixroute 地址标记。

## 应用

需要 systemd-networkd、iproute2、python3；不需要 dnsmasq。

```bash
cd ~/dev/envkit
sudo bash bootstrap/pi4b/setup.sh
bash bootstrap/pi4b/check.sh
```

从 SSH 首次迁移时，用独立的 systemd 任务运行，避免连接中断终止脚本：

```bash
sudo systemd-run --unit=pi4b-network-setup --collect \
  /bin/bash /home/zrx/dev/envkit/bootstrap/pi4b/setup.sh
sudo journalctl -u pi4b-network-setup --no-pager
```

切换网络可能短暂中断连接，优先从 eth1 的 192.168.0.50 或本地控制台操作。
每次 setup 都在 `/var/backups/pi4b-network-时间戳/` 保存配置和原服务启用状态。
重复执行会跳过内容相同的配置文件。首次迁移的完整备份另存于
`/var/backups/pi-networkd-20260923T135932/`，包含 apply/rollback 脚本。
该次自动回退定时器已在验证成功后取消；setup.sh 本身不自动安排回退。

## 校园认证与代理

服务仍使用 `services/compose.yml`：

- auth-thu 和 auth-thu-deauth 使用独立 UID/GID `61001:61001` 和校园 DNS。
  这个 UID 保留给认证容器，不要用于其他应用。
- sing-box 的 TUN 设置 `exclude_uid: [61001]`，认证、DNS、联网检查都不经过代理。
- TUN 的 `exclude_interface: ["eth1"]` 保证直连电脑访问 Pi 的本地服务时
  不被透明代理重定向；eth1 不作为电脑的默认网关。
- 这些排除项也写入 `services/apps/sing-box/subscribe_update.py`，
  更新订阅后不会丢失。
- sing-box 其余 DNS 分流沿用现有配置。auth-thu 健康后启动 sing-box 的依赖保持不变。

应用 Compose 修改时只重建认证服务，避免执行 deauth：

```bash
docker compose -f services/compose.yml config --quiet
docker compose -f services/compose.yml up -d --no-deps auth-thu
```

## 验证

`check.sh` 检查服务归属、地址及路由。联网后还可以检查：

```bash
docker inspect --format '{{.State.Health.Status}} {{.RestartCount}}' auth-thu
docker logs --tail 10 auth-thu
curl --noproxy '*' -I --max-time 10 https://www.baidu.com/
curl -x http://127.0.0.1:7890 -I --max-time 10 https://www.google.com/generate_204
# 在直连电脑上检查访问：
ssh pi-local
# macOS 查看直连接口的 DHCP 租约，应无 router / domain_name_server：
ipconfig getpacket en7
```

2026-09-23 验证：校园 DHCPv4 / DHCPv6 获取成功；直连电脑重新获取的实际
DHCP ACK 分配了 192.168.0.67，租期 12h，不含 Router 或 DNS 选项。
ssh pi-local 可用，auth-thu 保持 healthy、重启次数为 0。
已有客户端需要续租才能移除缓存的旧 DNS 选项；macOS 可在网络设置中更新 DHCP 租约。
