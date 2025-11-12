#!/bin/bash
# Setup script for Build4 (ll-ACSBuilder4)

set -e

SERVER_ID="build4"
SERVER_IP="10.1.3.181"
REPO_DIR="/root/Build"

echo "Setting up Build4 coordination..."

HELPER_SRC="$REPO_DIR/scripts/sendmessages"
if [ -f "$HELPER_SRC" ]; then
    chmod +x "$HELPER_SRC" 2>/dev/null || true
    ln -sf "$HELPER_SRC" /usr/local/bin/sendmessages
    ln -sf /usr/local/bin/sendmessages /usr/local/bin/sm
    cat <<'EOF' >/etc/profile.d/build-messaging.sh
alias sm='sendmessages'
EOF
    chmod 644 /etc/profile.d/build-messaging.sh 2>/dev/null || true
    echo "[OK] Messaging helper installed (use 'sm')."
fi

# Configure git
git config user.email "build4@coordination.local"
git config user.name "Build4-ACSBuilder4"

# Create necessary directories
mkdir -p /root/build-logs
mkdir -p /root/artifacts/build4/debs

# Update status
cd "$REPO_DIR"
git pull origin main

jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.timestamp = $ts | .status = "idle" | .manager = "Initializing"' \
   build4/status.json > /tmp/status.json
mv /tmp/status.json build4/status.json

jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.timestamp = $ts | .healthy = true' \
   build4/heartbeat.json > /tmp/heartbeat.json
mv /tmp/heartbeat.json build4/heartbeat.json

git add build4/
git commit -m "Build4 setup initialized"
git push origin main

echo "Build4 setup complete!"
echo "Remember to start heartbeat: nohup ./heartbeat_build4.sh &"
