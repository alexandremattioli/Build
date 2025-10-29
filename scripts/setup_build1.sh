#!/bin/bash
# setup_build1.sh - Automated setup for Build1 (Codex - 10.1.3.175)
# Run this script to set up communication framework on Build1

set -euo pipefail

echo "=== Build1 Communication Framework Setup ==="
echo "Server: Build1 (10.1.3.175) - Managed by Codex"
echo "Starting setup at $(date)"
echo ""

# Check if already setup
if [ -d "/root/Build/.git" ]; then
    echo "⚠️  Warning: /root/Build already exists"
    read -p "Do you want to re-clone? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping clone. Using existing repository."
        cd /root/Build
        git pull origin main
    else
        rm -rf /root/Build
    fi
fi

# 1. Clone repository
if [ ! -d "/root/Build/.git" ]; then
    echo "[1/5] Cloning communication repository..."
    cd /root
    git clone https://github.com/alexandremattioli/Build.git
    echo "✓ Repository cloned"
else
    echo "[1/5] Repository already exists"
fi

# 2. Configure git
echo "[2/5] Configuring git..."
cd /root/Build
git config user.name "Build1 Codex"
git config user.email "codex@build1.local"
echo "✓ Git configured"

# 3. Make scripts executable
echo "[3/5] Setting script permissions..."
chmod +x scripts/*.sh
echo "✓ Scripts are executable"

# 4. Stop existing heartbeat daemon (if running)
echo "[4/5] Checking for existing heartbeat daemon..."
if pgrep -f "heartbeat_daemon.sh build1" > /dev/null; then
    echo "  Stopping existing heartbeat daemon..."
    pkill -f "heartbeat_daemon.sh build1" || true
    sleep 2
fi

# 5. Start heartbeat daemon
echo "[5/5] Starting enhanced heartbeat daemon..."
cd /root/Build/scripts
nohup ./enhanced_heartbeat_daemon.sh build1 60 > /var/log/heartbeat-build1.log 2>&1 &
DAEMON_PID=$!
sleep 2

# Verify daemon is running
if ps -p $DAEMON_PID > /dev/null; then
    echo "✓ Heartbeat daemon started (PID: $DAEMON_PID)"
else
    echo "⚠️  Warning: Heartbeat daemon may not have started properly"
    echo "  Check logs: tail -f /var/log/heartbeat-build1.log"
fi

echo ""
echo "=== Setup Complete for Build1 ==="
echo ""
echo "Status:"
echo "  Server: Build1 (10.1.3.175)"
echo "  Manager: Codex"
echo "  Repository: /root/Build"
echo "  Heartbeat: Running (every 60 seconds)"
echo "  Messages: Auto-checked with heartbeat"
echo "  Logs: /var/log/heartbeat-build1.log"
echo ""
echo "Verify with:"
echo "  cd /root/Build/scripts && ./check_health.sh"
echo ""
echo "Send test message to Build2:"
echo "  cd /root/Build/scripts"
echo "  ./send_message.sh build1 build2 info 'Hello' 'Build1 online'"
echo ""
echo "View heartbeat logs:"
echo "  tail -f /var/log/heartbeat-build1.log"
echo ""
echo "View messages:"
echo "  cd /root/Build/scripts && ./read_messages.sh build1"
echo ""
