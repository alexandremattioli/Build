#!/bin/bash
# setup_build1.sh - Automated setup for Build1 (Codex - 10.1.3.175)
# Run this script to set up communication framework on Build1

set -euo pipefail

# Flags
# - Default behavior: ALWAYS re-clone for latest code (recommended for automation)
# - Use --skip-reclone to keep existing repo and just pull updates
# - Use FORCE_RECLONE=0 env var to prevent auto-reclone
FORCE_RECLONE_ENV="${FORCE_RECLONE:-1}"
FORCE_RECLONE=1
SKIP_RECLONE=0

while [[ ${1:-} =~ ^- ]]; do
    case "$1" in
        --skip-reclone)
            SKIP_RECLONE=1
            FORCE_RECLONE=0
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--skip-reclone]" >&2
            exit 2
            ;;
    esac
done

# Env var override (allow disabling auto-reclone)
if [[ "$FORCE_RECLONE_ENV" == "0" ]]; then
    FORCE_RECLONE=0
fi

echo "=== Build1 Communication Framework Setup ==="
echo "Server: Build1 (10.1.3.175) - Managed by Codex"
echo "Starting setup at $(date)"
echo ""

# Check if already setup
if [ -d "/root/Build/.git" ]; then
    echo "⚠️  Warning: /root/Build already exists"
    if [[ $FORCE_RECLONE -eq 1 ]]; then
        echo "Re-cloning repository for latest code (default behavior)..."
        echo "Use --skip-reclone to keep existing repo."
        rm -rf /root/Build
    elif [[ $SKIP_RECLONE -eq 1 ]]; then
        echo "--skip-reclone specified. Using existing repository."
        cd /root/Build
        git pull --rebase origin main
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
