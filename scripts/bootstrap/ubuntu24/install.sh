#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root" >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  python3 python3-venv python3-distutils \
  arping jq iproute2 curl ca-certificates openssl

mkdir -p /opt/build-agent /var/lib/build /etc/build

# Install files from repo (assumes files are already present if run from cloned repo)
if [[ -f "$(dirname "$0")/agent-runner.sh" ]]; then
  SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
  install -m 0755 "$SRC_DIR/agent-runner.sh" /opt/build-agent/agent-runner.sh
  install -m 0755 "$SRC_DIR/bootstrap.sh" /opt/build-agent/bootstrap.sh
  install -m 0644 "$SRC_DIR/network_utils.sh" /opt/build-agent/network_utils.sh
  install -m 0644 "$SRC_DIR/build-agent.service" /etc/systemd/system/build-agent.service
  install -m 0644 "$SRC_DIR/peer_agent.py" /opt/build-agent/peer_agent.py
  install -m 0644 "$SRC_DIR/advisor.py" /opt/build-agent/advisor.py
  install -m 0644 "$SRC_DIR/build-advisor.service" /etc/systemd/system/build-advisor.service
  install -m 0644 "$SRC_DIR/message_bridge.py" /opt/build-agent/message_bridge.py
  install -m 0755 "$SRC_DIR/hive" /usr/local/bin/hive
else
  echo "Installing via raw GitHub"
  BASE="https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24"
  curl -fsSL "$BASE/agent-runner.sh" -o /opt/build-agent/agent-runner.sh && chmod 0755 /opt/build-agent/agent-runner.sh
  curl -fsSL "$BASE/bootstrap.sh" -o /opt/build-agent/bootstrap.sh && chmod 0755 /opt/build-agent/bootstrap.sh
  curl -fsSL "$BASE/network_utils.sh" -o /opt/build-agent/network_utils.sh && chmod 0644 /opt/build-agent/network_utils.sh
  curl -fsSL "$BASE/peer_agent.py" -o /opt/build-agent/peer_agent.py && chmod 0644 /opt/build-agent/peer_agent.py
  curl -fsSL "$BASE/advisor.py" -o /opt/build-agent/advisor.py && chmod 0644 /opt/build-agent/advisor.py
  curl -fsSL "$BASE/message_bridge.py" -o /opt/build-agent/message_bridge.py && chmod 0644 /opt/build-agent/message_bridge.py
  curl -fsSL "$BASE/build-agent.service" -o /etc/systemd/system/build-agent.service && chmod 0644 /etc/systemd/system/build-agent.service
  curl -fsSL "$BASE/build-advisor.service" -o /etc/systemd/system/build-advisor.service && chmod 0644 /etc/systemd/system/build-advisor.service
  curl -fsSL "$BASE/hive" -o /usr/local/bin/hive && chmod 0755 /usr/local/bin/hive
fi

# Create a default shared secret if not present
if [[ ! -f /etc/build/shared_secret ]]; then
  openssl rand -hex 16 > /etc/build/shared_secret
  chmod 0600 /etc/build/shared_secret
  echo "Generated new shared secret at /etc/build/shared_secret"
  echo "Copy this to other nodes BEFORE running install on them:"
  cat /etc/build/shared_secret
fi

systemctl daemon-reload
systemctl enable --now build-agent.service
systemctl enable --now build-advisor.service

echo ""
echo "Install complete."
echo "Agent logs:   journalctl -u build-agent -f"
echo "Advisor logs: journalctl -u build-advisor -f"
echo "Hive status:  hive status"
echo "List peers:   hive peers"
echo "Reset role:   sudo hive reset"
