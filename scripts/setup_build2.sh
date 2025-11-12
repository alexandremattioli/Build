#!/bin/bash
# setup_build2.sh - Automated setup/recovery for Build2 (GitHub Copilot - 10.1.3.177)
# Run this script to set up or recover the communication framework on Build2

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

echo "=== Build2 Communication Framework Setup/Recovery ==="
echo "Starting at $(date)"
echo ""

# Check if already setup
if [ -d "/root/Build/.git" ]; then
    echo "[!]  Warning: /root/Build already exists"
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
    echo "[1/8] Cloning communication repository..."
    cd /root
    git clone https://github.com/alexandremattioli/Build.git
    echo "[OK] Repository cloned"
else
    echo "[1/8] Repository already exists"
fi

# 2. Configure git
echo "[2/8] Configuring git..."
cd /root/Build
git config user.name "Build2 Copilot"
git config user.email "copilot@build2.local"

# Configure GitHub authentication if /PAT exists
if [ -f "/PAT" ] && [ -s "/PAT" ]; then
    echo "  Configuring GitHub auth from /PAT"
    TOKEN=$(head -n1 /PAT | tr -d '\r\n')
    chmod 600 /PAT 2>/dev/null || true
    git config credential.helper store
    CRED_FILE="/root/.git-credentials"
    touch "$CRED_FILE"
    chmod 600 "$CRED_FILE"
    if grep -q "github.com" "$CRED_FILE"; then
        sed -i '/github.com/d' "$CRED_FILE"
    fi
    printf "https://x-access-token:%s@github.com\n" "$TOKEN" >> "$CRED_FILE"
    echo "[OK] GitHub auth configured via credential helper"
else
    echo "[!]  /PAT not found or empty; pushes may require interactive auth or SSH keys"
fi

echo "[OK] Git configured"

# 3. Make scripts executable
echo "[3/8] Setting script permissions..."
chmod +x scripts/*.sh
chmod +x scripts/sendmessages 2>/dev/null || true
echo "[OK] Scripts are executable"

# 4. Install messaging helper + alias
echo "[4/8] Installing messaging helper and alias..."
HELPER_SRC="/root/Build/scripts/sendmessages"
HELPER_DST="/usr/local/bin/sendmessages"
ln -sf "$HELPER_SRC" "$HELPER_DST"
ln -sf "$HELPER_DST" /usr/local/bin/sm
cat <<'EOF' >/etc/profile.d/build-messaging.sh
alias sm='sendmessages'
EOF
chmod 644 /etc/profile.d/build-messaging.sh 2>/dev/null || true
echo "[OK] Messaging helper installed (use 'sm')."

# 5. Read entire conversation thread (REQUIRED on first setup)
echo "[5/8] Reading conversation thread..."
echo "════════════════════════════════════════════════════════════════"
echo " IMPORTANT: Build servers must read the entire conversation"
echo " history to understand context and previous communications."
echo "════════════════════════════════════════════════════════════════"
cd /root/Build/scripts
./read_conversation_thread.sh build2 --limit 10
echo ""
echo "[OK] Conversation thread reviewed (showing last 10 messages)"
echo ""
echo "To read full conversation history, run:"
echo "  cd /root/Build/scripts && ./read_conversation_thread.sh build2"
echo ""

# 6. Check for unread messages
echo "[6/8] Checking for unread messages..."
cd /root/Build/scripts
if ./check_unread_messages.sh build2; then
    echo "[OK] No unread messages"
else
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo " [!]  YOU HAVE UNREAD MESSAGES!"
    echo " Please review and respond to unread messages before proceeding."
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "To view all unread messages:"
    echo "  cd /root/Build/scripts && ./read_conversation_thread.sh build2 --unread-only"
    echo ""
    echo "To mark messages as read after reviewing:"
    echo "  cd /root/Build/scripts && ./mark_messages_read.sh build2"
    echo ""
fi

# 7. Stop existing heartbeat daemon (if running)
echo "[7/8] Checking for existing heartbeat daemons..."
pkill -f "heartbeat_daemon.sh build2" 2>/dev/null || true
pkill -f "enhanced_heartbeat_daemon.sh build2" 2>/dev/null || true
sleep 1

# 8. Start heartbeat daemon
echo "[8/8] Starting enhanced heartbeat daemon..."
cd /root/Build/scripts
nohup ./enhanced_heartbeat_daemon.sh build2 60 > /var/log/heartbeat-build2.log 2>&1 &
DAEMON_PID=$!
sleep 2

# Verify daemon is running
if ps -p $DAEMON_PID > /dev/null; then
    echo "[OK] Heartbeat daemon started (PID: $DAEMON_PID)"
else
    echo "[!]  Warning: Heartbeat daemon may not have started properly"
    echo "  Check logs: tail -f /var/log/heartbeat-build2.log"
fi

echo ""
echo "=== Setup/Recovery Complete ==="
echo ""
echo "Status:"
echo "  Repository: /root/Build"
echo "  Heartbeat: Running (every 60 seconds)"
echo "  Messages: Auto-checked with heartbeat"
echo "  Logs: /var/log/heartbeat-build2.log"
echo ""
echo "IMPORTANT COMMANDS:"
echo "  Check unread messages:"
echo "    cd /root/Build/scripts && ./check_unread_messages.sh build2"
echo ""
echo "  Read full conversation thread:"
echo "    cd /root/Build/scripts && ./read_conversation_thread.sh build2"
echo ""
echo "  View only unread messages:"
echo "    cd /root/Build/scripts && ./read_conversation_thread.sh build2 --unread-only"
echo ""
echo "  Mark messages as read:"
echo "    cd /root/Build/scripts && ./mark_messages_read.sh build2"
echo ""
echo "  Send a message:"
echo "    sm 1 \"Subject\" \"Body text\"  # Alias for sendmessages helper"
echo ""
echo "  Update message status:"
echo "    cd /root/Build/scripts && ./update_message_status_txt.sh"
echo ""
echo "  Check system health:"
echo "    cd /root/Build/scripts && ./check_health.sh"
echo ""
echo "View heartbeat logs:"
echo "  tail -f /var/log/heartbeat-build2.log"
echo ""
