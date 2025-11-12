#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/network_utils.sh"

IFACE=$(get_primary_iface)
CIDR=$(get_iface_cidr "$IFACE")
export CIDR
BROADCAST=$(python3 - <<'PY'
import ipaddress, os
cidr=os.environ.get('CIDR')
net=ipaddress.ip_network(cidr, strict=False)
print(str(net.broadcast_address))
PY
)
NEXTIP=$(find_next_free_ip "$IFACE" "$CIDR" 50 || true)

cat <<EOF
Interface : $IFACE
Address   : $CIDR
Broadcast : $BROADCAST
Next free : ${NEXTIP:-<none found>}
EOF

# Optional: claim the IP as a secondary address if requested
if [[ "${1:-}" == "--claim" && -n "${NEXTIP:-}" ]]; then
  MASK=$(echo "$CIDR" | cut -d'/' -f2)
  ip addr add "$NEXTIP/$MASK" dev "$IFACE"
  echo "Claimed $NEXTIP/$MASK on $IFACE"
fi
