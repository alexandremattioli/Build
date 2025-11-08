#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root" >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  python3 python3-venv python3-distutils \
  arping jq iproute2 curl ca-certificates

mkdir -p /opt/build-agent /var/lib/build /etc/build

# Install files from repo (assumes files are already present if run from cloned repo)
if [[ -f "$(dirname "$0")/agent-runner.sh" ]]; then
  SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
  install -m 0755 "$SRC_DIR/agent-runner.sh" /opt/build-agent/agent-runner.sh
  install -m 0755 "$SRC_DIR/bootstrap.sh" /opt/build-agent/bootstrap.sh
  install -m 0644 "$SRC_DIR/network_utils.sh" /opt/build-agent/network_utils.sh
  install -m 0644 "$SRC_DIR/build-agent.service" /etc/systemd/system/build-agent.service
  install -m 0644 "$SRC_DIR/peer_agent.py" /opt/build-agent/peer_agent.py
else
  echo "Installing via raw GitHub"
  BASE="https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24"
  curl -fsSL "$BASE/agent-runner.sh" -o /opt/build-agent/agent-runner.sh && chmod 0755 /opt/build-agent/agent-runner.sh
  curl -fsSL "$BASE/bootstrap.sh" -o /opt/build-agent/bootstrap.sh && chmod 0755 /opt/build-agent/bootstrap.sh
  curl -fsSL "$BASE/network_utils.sh" -o /opt/build-agent/network_utils.sh && chmod 0644 /opt/build-agent/network_utils.sh
  curl -fsSL "$BASE/peer_agent.py" -o /opt/build-agent/peer_agent.py && chmod 0644 /opt/build-agent/peer_agent.py
  curl -fsSL "$BASE/build-agent.service" -o /etc/systemd/system/build-agent.service && chmod 0644 /etc/systemd/system/build-agent.service
fi

# Create a default shared secret if not present
if [[ ! -f /etc/build/shared_secret ]]; then
  openssl rand -hex 16 > /etc/build/shared_secret
  chmod 0600 /etc/build/shared_secret
fi

systemctl daemon-reload
systemctl enable --now build-agent.service

echo "Install complete. Logs: journalctl -u build-agent -f"
