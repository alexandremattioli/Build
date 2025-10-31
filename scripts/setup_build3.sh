#!/bin/bash
# Setup script for Build3 (ll-ACSBuilder3)

set -e

SERVER_ID="build3"
SERVER_IP="10.1.3.179"
REPO_DIR="/root/Build"

echo "Setting up Build3 coordination..."

# Configure git
git config user.email "build3@coordination.local"
git config user.name "Build3-ACSBuilder3"

# Create necessary directories
mkdir -p /root/build-logs
mkdir -p /root/artifacts/build3/debs

# Update status
cd "$REPO_DIR"
git pull origin main

jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.timestamp = $ts | .status = "idle" | .manager = "Initializing"' \
   build3/status.json > /tmp/status.json
mv /tmp/status.json build3/status.json

jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.timestamp = $ts | .healthy = true' \
   build3/heartbeat.json > /tmp/heartbeat.json
mv /tmp/heartbeat.json build3/heartbeat.json

git add build3/
git commit -m "Build3 setup initialized"
git push origin main

echo "Build3 setup complete!"
echo "Remember to start heartbeat: nohup ./heartbeat_build3.sh &"
