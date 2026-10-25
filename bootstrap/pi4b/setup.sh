#!/usr/bin/env bash
set -euo pipefail

SHELL_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_DIR=$(dirname "$(dirname "$SHELL_DIR")")
SCRIPTS_DIR="$PROJECT_DIR/scripts"
. "$SCRIPTS_DIR/color.sh"
. "$SCRIPTS_DIR/log.sh"
. "$SCRIPTS_DIR/func.sh"

# 和 bootstrap/arch/bootstrap.sh 一样，系统配置需要以 root 运行
if [[ "$EUID" -ne 0 ]]; then
    error "Run with sudo bash $SHELL_DIR/setup.sh (see README.md for SSH migration)."
    exit 1
fi

for tool in networkctl systemctl ip python3; do
    command -v "$tool" >/dev/null || { error "Missing dependency: $tool"; exit 1; }
done
ip link show eth0 >/dev/null
ip link show eth1 >/dev/null

# 除了 copy() 对单个文件的备份外，再保留一份完整快照
snapshot_dir="/var/backups/pi4b-network-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$snapshot_dir"
for path in /etc/systemd/network /etc/systemd/networkd.conf.d \
            /etc/NetworkManager /run/NetworkManager/system-connections \
            /etc/dhcpcd.conf /etc/dnsmasq.conf /etc/resolv.conf; do
    if [[ -e "$path" || -L "$path" ]]; then
        mkdir -p "$snapshot_dir$(dirname "$path")"
        cp -a "$path" "$snapshot_dir$path"
    fi
done
systemctl is-enabled NetworkManager dhcpcd dnsmasq systemd-networkd \
    > "$snapshot_dir/unit-states.txt" 2>&1 || true
info "Network backup: $snapshot_dir"

# 把网卡交给 networkd 之前，先停掉原来的 DHCP 客户端和服务端
for unit in NetworkManager.service dhcpcd.service dnsmasq.service; do
    if systemctl cat "$unit" >/dev/null 2>&1; then
        systemctl stop "$unit"
        systemctl disable "$unit"
    fi
    systemctl mask "$unit"
done

for path in \
    systemd/network/10-eth0.network \
    systemd/network/20-eth1.network \
    systemd/networkd.conf.d/20-external-routing.conf \
    sysctl.d/90-nonlocal-bind.conf \
    resolv.conf; do
    # resolv.conf 如果是软链接，先把软链接本身备份，再复制普通文件
    if [[ "$path" == resolv.conf && -L /etc/resolv.conf ]]; then
        backup /etc/resolv.conf
    fi
    copy "$SHELL_DIR/etc/$path" "/etc/$path"
done

# 清理错误的 DHCP 服务器下发、残留下来的地址和路由（如果有）
python3 - <<'PY'
import ipaddress, json, subprocess
bad_subnet = ipaddress.ip_network("192.168.31.0/24")
for link in json.loads(subprocess.check_output(["ip", "-j", "-4", "address", "show", "dev", "eth0"])):
    for address in link["addr_info"]:
        if ipaddress.ip_address(address["local"]) in bad_subnet:
            subprocess.run(["ip", "address", "del", f'{address["local"]}/{address["prefixlen"]}', "dev", "eth0"], check=True)
for route in json.loads(subprocess.check_output(["ip", "-j", "-4", "route", "show", "default"])):
    if route.get("dev") == "eth0" and route.get("gateway") == "192.168.31.1":
        subprocess.run(["ip", "route", "del", "default", "via", "192.168.31.1", "dev", "eth0"], check=True)
PY

# 90-nonlocal-bind.conf：让 sing-box 能在 tailscaled 启动前绑定 tailnet IP
sysctl -p /etc/sysctl.d/90-nonlocal-bind.conf

systemctl enable --now systemd-networkd.service
networkctl reload
ok "networkd manages eth0/eth1; direct clients receive an address without gateway or DNS."
info "Run bash $SHELL_DIR/check.sh to inspect addresses, DHCP ownership and service health."
