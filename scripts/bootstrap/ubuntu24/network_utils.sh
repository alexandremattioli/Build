#!/usr/bin/env bash
set -euo pipefail

get_primary_iface() {
  ip route | awk '/^default/ {print $5; exit}'
}

get_iface_cidr() {
  local iface="$1"
  ip -o -f inet addr show dev "$iface" | awk '{print $4}' | head -n1
}

# Returns 0 if host responds (used=true), 1 if free
host_used() {
  local iface="$1" ipaddr="$2"
  if command -v arping >/dev/null 2>&1; then
    arping -I "$iface" -c 1 -w 1 "$ipaddr" >/dev/null 2>&1 && return 0 || return 1
  else
    ping -c 1 -W 1 "$ipaddr" >/dev/null 2>&1 && return 0 || return 1
  fi
}

# Find next free IP in CIDR, starting from host+1, skipping network/broadcast
find_next_free_ip() {
  local iface="$1" cidr="$2" max_scan="${3:-50}"
  python3 - "$iface" "$cidr" "$max_scan" <<'PY'
import ipaddress, os, sys, subprocess
iface, cidr, max_scan = sys.argv[1], sys.argv[2], int(sys.argv[3])
net = ipaddress.ip_network(cidr, strict=False)
# pick a start near current host + 1
cur = ipaddress.ip_interface(cidr).ip
hosts = list(net.hosts())
try:
    start_index = hosts.index(cur) + 1
except ValueError:
    start_index = 0
for i in range(start_index, min(start_index+max_scan, len(hosts))):
    candidate = str(hosts[i])
    # test with arping or ping
    used = subprocess.call(["bash","-c", f". /opt/build-agent/network_utils.sh; host_used '{iface}' '{candidate}'"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if used != 0:
        print(candidate)
        sys.exit(0)
print("")
PY
}
