#!/usr/bin/env bash
set -euo pipefail

systemctl is-active --quiet systemd-networkd.service
for unit in NetworkManager.service dhcpcd.service dnsmasq.service; do
    if systemctl is-active --quiet "$unit"; then
        echo "ERROR: $unit is still active" >&2
        exit 1
    fi
done

python3 - <<'PY'
import ipaddress, json, subprocess
def read(*args):
    return json.loads(subprocess.check_output(args))
links = {link["ifname"]: link for link in read("ip", "-j", "address")}
assert any(a["local"] == "192.168.0.50" and a["prefixlen"] == 24 for a in links["eth1"]["addr_info"]), "eth1 static address missing"
assert not any(ipaddress.ip_address(a["local"]) in ipaddress.ip_network("192.168.31.0/24") for a in links["eth0"]["addr_info"] if a["family"] == "inet"), "Rogue DHCP address remains"
routes = read("ip", "-j", "-4", "route", "show", "default")
assert routes and all(r.get("dev") == "eth0" and r.get("gateway") != "192.168.31.1" for r in routes), "Unexpected default route"
route = read("ip", "-j", "route", "get", "192.168.0.74")[0]
assert route["dev"] == "eth1", "Direct cable subnet route missing"
print("Address and route checks passed.")
PY
networkctl status eth0 eth1 --no-pager
if command -v docker >/dev/null; then
    docker ps --format 'table {{.Names}}\t{{.Status}}'
fi
