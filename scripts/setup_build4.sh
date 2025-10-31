#!/bin/bash
# Setup script for Build4 (ll-ACSBuilder4)

set -e

SERVER_ID="build4"
SERVER_IP="10.1.3.181"
REPO_DIR="/root/Build"

echo "Setting up Build4 coordination..."

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
