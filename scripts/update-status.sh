#!/bin/bash
# Update status.json for Linux build servers
# Run this script periodically via cron (every 60 seconds recommended)
# Add to crontab: * * * * * /path/to/update-status.sh

set -e

# Configuration
SERVER_CONFIG=".build_server_id"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_DIR"

# Read server configuration
if [ ! -f "$SERVER_CONFIG" ]; then
    echo "Error: Server config not found: $SERVER_CONFIG"
    exit 1
fi

SERVER_ID=$(jq -r '.server_id' "$SERVER_CONFIG")
IP=$(jq -r '.ip' "$SERVER_CONFIG")
MANAGER=$(jq -r '.manager' "$SERVER_CONFIG")

# Get system metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEMORY_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
MEMORY_USED=$(free -g | awk '/^Mem:/{print $3}')
DISK_FREE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
CORES=$(nproc)

# Get Java and Maven versions
JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
MAVEN_VERSION=$(mvn -version 2>&1 | awk '/Apache Maven/ {print $3}' | cut -d'.' -f1)

# Determine status
STATUS="online"
if [ $(echo "$CPU_USAGE > 80" | bc -l) -eq 1 ]; then
    STATUS="building"
fi

# Check for current job
CURRENT_JOB="null"
if [ -f "$SERVER_ID/current_job.json" ]; then
    CURRENT_JOB=$(cat "$SERVER_ID/current_job.json")
fi

# Get last build info
LAST_BUILD="null"
if [ -f "$SERVER_ID/last_build.json" ]; then
    LAST_BUILD=$(cat "$SERVER_ID/last_build.json")
fi

# Get last package info
LAST_PACKAGE="null"
if [ -f "$SERVER_ID/last_package.json" ]; then
    LAST_PACKAGE=$(cat "$SERVER_ID/last_package.json")
fi

# Build status JSON
cat > "$SERVER_ID/status.json" <<EOF
{
  "server": "$SERVER_ID",
  "ip": "$IP",
  "manager": "$MANAGER",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$STATUS",
  "current_job": $CURRENT_JOB,
  "last_build": $LAST_BUILD,
  "last_package": $LAST_PACKAGE,
  "system": {
    "cpu_usage": $(printf "%.1f" "$CPU_USAGE"),
    "memory_used_gb": $MEMORY_USED,
    "disk_free_gb": $DISK_FREE
  },
  "capabilities": {
    "cores": $CORES,
    "memory_gb": $MEMORY_TOTAL,
    "java_version": "$JAVA_VERSION",
    "maven_version": "${MAVEN_VERSION}.x",
    "build_profiles": ["systemvm", "developer"]
  }
}
EOF

# Commit and push to GitHub
git add "$SERVER_ID/status.json"
if ! git diff --cached --quiet; then
    git commit -m "Auto-update $SERVER_ID status"
    
    # Retry push up to 3 times with rebase
    for i in {1..3}; do
        sleep 2
        git pull --rebase origin main > /dev/null 2>&1 || true
        if git push origin main 2>&1 | grep -v "rejected"; then
            echo "Status updated and pushed successfully"
            break
        fi
    done
fi

echo "Status update completed at $(date)"
