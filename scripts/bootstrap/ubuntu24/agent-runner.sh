#!/usr/bin/env bash
set -euo pipefail

export PYTHONUNBUFFERED=1

IFACE="${IFACE:-}"
BROADCAST="${BROADCAST:-}"
NETCIDR="${NETCIDR:-}"

# Determine interface/network if not given
if [[ -z "${IFACE}" ]] || [[ -z "${NETCIDR}" ]]; then
  source /opt/build-agent/network_utils.sh
  IFACE=$(get_primary_iface)
  NETCIDR=$(get_iface_cidr "$IFACE")
  export NETCIDR
  BROADCAST=$(python3 - <<'PY'
import ipaddress, os
cidr=os.environ.get('NETCIDR')
net=ipaddress.ip_network(cidr, strict=False)
print(str(net.broadcast_address))
PY
)
fi

# Optional: compute next free IP (not assigned)
NEXTHOST=$(bash -c ". /opt/build-agent/network_utils.sh; find_next_free_ip '$IFACE' '$NETCIDR' 10") || true

exec /usr/bin/python3 /opt/build-agent/peer_agent.py \
  --iface "$IFACE" \
  --cidr "$NETCIDR" \
  ${BROADCAST:+--broadcast "$BROADCAST"} \
  ${NEXTHOST:+--candidate "$NEXTHOST"}
