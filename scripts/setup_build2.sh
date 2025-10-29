#!/bin/bash
# setup_build2.sh - Automated setup/recovery for Build2 (GitHub Copilot - 10.1.3.177)
# Run this script to set up or recover the communication framework on Build2

set -euo pipefail

# Flags
# - Use FORCE_RECLONE=1 env var or --force to always re-clone /root/Build if it exists
# - Use --skip-reclone to keep existing repo without prompt
FORCE_RECLONE_ENV="${FORCE_RECLONE:-0}"
FORCE_RECLONE=0
SKIP_RECLONE=0

while [[ ${1:-} =~ ^- ]]; do
    case "$1" in
        --force|-f)
            FORCE_RECLONE=1
            shift
            ;;
        --skip-reclone)
            SKIP_RECLONE=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--force|-f] [--skip-reclone]" >&2
            exit 2
            ;;
    esac
done

# Env var override
if [[ "$FORCE_RECLONE_ENV" == "1" ]]; then
    FORCE_RECLONE=1
fi

echo "=== Build2 Communication Framework Setup/Recovery ==="
echo "Starting at $(date)"
echo ""

# Check if already setup
if [ -d "/root/Build/.git" ]; then
    echo "⚠️  Warning: /root/Build already exists"
    if [[ $FORCE_RECLONE -eq 1 ]]; then
        echo "--force specified (or FORCE_RECLONE=1). Re-cloning repository..."
        rm -rf /root/Build
    elif [[ $SKIP_RECLONE -eq 1 ]]; then
        echo "--skip-reclone specified. Using existing repository."
        cd /root/Build
        git pull --rebase origin main
    else
        read -p "Do you want to re-clone? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping clone. Using existing repository."
            cd /root/Build
            git pull --rebase origin main
        else
            rm -rf /root/Build
        fi
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
git config user.name "Build2 Copilot"
git config user.email "copilot@build2.local"
echo "✓ Git configured"

# 3. Make scripts executable
echo "[3/5] Setting script permissions..."
chmod +x scripts/*.sh
echo "✓ Scripts are executable"

# 4. Stop existing heartbeat daemon (if running)
echo "[4/5] Checking for existing heartbeat daemons..."
pkill -f "heartbeat_daemon.sh build2" 2>/dev/null || true
pkill -f "enhanced_heartbeat_daemon.sh build2" 2>/dev/null || true
sleep 1

# 5. Start heartbeat daemon
echo "[5/5] Starting enhanced heartbeat daemon..."
cd /root/Build/scripts
nohup ./enhanced_heartbeat_daemon.sh build2 60 > /var/log/heartbeat.log 2>&1 &
DAEMON_PID=$!
sleep 2

# Verify daemon is running
if ps -p $DAEMON_PID > /dev/null; then
    echo "✓ Heartbeat daemon started (PID: $DAEMON_PID)"
else
    echo "⚠️  Warning: Heartbeat daemon may not have started properly"
    echo "  Check logs: tail -f /var/log/heartbeat.log"
fi

echo ""
echo "=== Setup/Recovery Complete ==="
echo ""
echo "Status:"
echo "  Repository: /root/Build"
echo "  Heartbeat: Running (every 60 seconds)"
echo "  Messages: Auto-checked with heartbeat"
echo "  Logs: /var/log/heartbeat.log"
echo ""
echo "Verify with:"
echo "  cd /root/Build/scripts && ./check_health.sh"
echo ""
echo "View heartbeat logs:"
echo "  tail -f /var/log/heartbeat.log"
echo ""
echo "View messages:"
echo "  cd /root/Build/scripts && ./read_messages.sh build2"
echo ""
