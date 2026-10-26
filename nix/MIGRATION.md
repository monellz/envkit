# hub：Debian → NixOS 迁移清单

hub（树莓派 4）从 SD 卡上的 Debian（docker compose）迁移到本 flake 描述的 NixOS。
可以全程远程完成：NixOS 先用树莓派固件的 tryboot「只试启动一次」，失败时重启就自动回到 Debian。
迁移由 Mac 上的 Claude Code 经 ssh 操作 hub：会话跑在 Mac 上（用 Mac 本机的 sing-box 访问海外），hub 重启、试启动、退回 Debian 都不会中断它。

## 布局

| 位置 | 内容 |
| --- | --- |
| SD 卡启动分区（FAT，`/boot/firmware`） | Debian 的 `config.txt` 不动；新增启动位 `nixos-try/`（待试启动）、`nixos/`（已确认）和 `tryboot.txt`，由 `hub-boot` 管理 |
| SD 卡根分区（ext4） | Debian，原样保留，作为回退系统 |
| 数据盘 btrfs 子卷 `@nixos` | NixOS 的根文件系统 |
| 数据盘 btrfs 顶层 `/mnt/disk` | gitea / vaultwarden / webdav 等数据，两个系统共用 |

## 自动回退

tryboot 只对下一次开机生效，之后任何一次重启都回到 `config.txt`（Debian）。NixOS 试启动期间：

| 失败情况 | 回退方式 |
| --- | --- |
| 内核崩溃 / initrd 找不到根分区 | `panic=10` + `boot.panic_on_fail`：自动重启 |
| 系统卡死 | 硬件看门狗（systemd 喂狗）：自动重启 |
| 起来了但网络 / 认证 / ssh 不通 | 超时未确认自动重启：启动后开始倒计时，到时间还没有登录执行确认命令，就自动重启 |
| 固件在加载内核前卡住 | **无法自动恢复**，需要断电重启一次（智能插座或现场） |

## 一、准备（在 Debian 上，不影响线上）

- [ ] `nix flake check` 通过；hub 系统构建通过
- [x] agents-hub：本 flake 尚未包含它，迁移后 `https://hub.<tailnet>.ts.net/` 暂时不可用（已接受）
- [x] Claude Code：不在 hub 上运行，改在 Mac 上经 ssh 操作 hub
- [ ] Mac 上能经 ssh 登录 hub（公网 166.111.238.16:3333 和 tailnet 两条路都试一下）
- [ ] 备份管理密钥 `~/.config/sops/age/keys.txt`（已存 vaultwarden）

## 二、搬状态（在 Debian 上）

- [ ] 停止 gitea、vault、webdav 容器（保证 sqlite 一致；不要停 sing-box、auth-thu）
- [ ] 数据盘做只读快照：`btrfs subvolume snapshot -r /mnt/disk /mnt/disk/.snapshots/pre-nixos-<日期>`
- [ ] 创建子卷 `@nixos`，挂载到临时目录，安装系统闭包（`nixos-install --system <闭包> --no-bootloader`）
- [ ] 复制到新根：
  - [ ] `/etc/ssh/ssh_host_*`：主机身份（各设备记录的指纹不变）+ sops-nix 解密密钥
  - [ ] `/var/lib/tailscale/`：节点身份（hub / 100.66.22.71 / *.ts.net 证书）
  - [ ] 飞连登录状态：容器内 `/opt/Corplink/` 下除程序外的文件 → `/var/lib/corplink/opt/`；`/usr/local/etc/corplink/udid` → `/var/lib/corplink/etc/`
  - [ ] sing-box 的 `cache.db`（docker 卷 `my_sing-box-data`）→ `/var/lib/sing-box/`（可选，保留节点选择）
  - [ ] `~zrx`：`~/.config/sops/age/keys.txt`、`~/.ssh/`（私钥、known_hosts）、`~/dev/envkit`、`~/.claude` 等需要的家目录内容
- [ ] `hub-boot install <系统闭包>`：把内核、initrd、设备树、cmdline 写进 SD 启动分区的 `nixos-try/`，并写 `tryboot.txt`

## 三、试启动

- [ ] 重启服务器上的 `ssh -R` 常驻转发前先记下它们（重启后要重新建立）
- [ ] `sudo reboot '0 tryboot'`（Debian 上没有 hub-boot；NixOS 上以后用 `hub-boot try`）
- [ ] 在倒计时结束前经公网 ssh（166.111.238.16:3333）或 tailnet 登录，逐项验证（第四节）
- [ ] 全部通过后执行 `hub-boot confirm`（取消倒计时）

## 四、验证

- [ ] 公网 ssh 3333 可登录；主机指纹没变
- [ ] 校园网认证：`systemctl status auth-thu` 在线；IP 仍是 166.111.238.16
- [ ] tailscale：节点名 hub、地址 100.66.22.71；`tailscale serve status` 各路径都在
- [ ] sing-box：`curl -x http://127.0.0.1:7890 https://claude.ai/cdn-cgi/trace` 出口不是 CN；baidu 直连正常
- [ ] corplink：`podman ps` 健康；经 1088 访问 git.qcjzai.cn 正常（没有要求重新扫码）
- [ ] gitea：网页 `/gitea/`、`git ls-remote git@gitea:...` 正常；仓库、用户都在；版本升级的数据库迁移成功
- [ ] vaultwarden：Bitwarden 客户端能同步
- [ ] webdav：`/dav/` 用新密码能登录，Zotero 同步正常
- [ ] `/sing-box/` 发布的客户端配置能下载，Mac 的 `sync_sing_box.sh` 正常
- [ ] tailnet-gateway-in（100.66.22.71:7890，带认证）可用
- [ ] 9870：重新建立服务器的 `ssh -R` 转发后，服务器上经 9870 访问公网正常
- [ ] 数据目录属主已改为各服务用户（gitea / vaultwarden / webdav）

## 五、确认切换

- [ ] `hub-boot confirm` 会把 `config.txt` 改为启动 NixOS，Debian 的原配置另存为 `config-debian.txt`
- [ ] 观察一段时间（重启一次，确认能正常起来）
- [ ] 之后再清理：Debian 上的 docker 镜像和卷、`services/` 下的旧部署文件、git-crypt 加密的旧密钥

## 回滚

- 试启动阶段：任何一次重启都会回到 Debian
- 确认切换之后：把 `config-debian.txt` 恢复为 `config.txt` 并重启
- 回到 Debian 后：
  - gitea 的数据库已被新版本升级，需要从快照恢复 `/mnt/disk/gitea`
  - vaultwarden / webdav 的容器以 root 运行，属主变化不影响；但 NixOS 期间的写入会保留
  - 重新启动 docker 容器：`docker compose up -d --no-deps gitea vault webdav`

## 以后的部署

```bash
cd ~/dev/envkit/nix
sudo nixos-rebuild boot --flake .#hub   # 新系统写进 nixos-try/，不影响正在运行的系统
sudo hub-boot try                       # 重启并试启动；超时未确认自动回到 nixos/
sudo hub-boot confirm                   # 验证通过后，提升为默认启动
```

不涉及内核和启动的改动也可以直接 `nixos-rebuild switch` 生效（但下次开机仍启动 nixos/ 里已确认的系统，直到再走一次 try / confirm）。

## 注意

- hub 上原来的 Claude Code 会话运行在 Debian 上，重启后结束；迁移改由 Mac 上的 Claude Code 进行
- `ssh -R` 常驻转发（tmux `alive`）、agents-hub、各 tmux 会话在重启后都不会自动恢复
