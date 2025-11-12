# Quick Start Guide

## Initial Setup

### 1. Clone Repository on Both Servers

On Build1 (10.1.3.175):
```bash
cd /root
git clone https://github.com/alexandremattioli/Build.git
cd Build
```

On Build2 (10.1.3.177):
```bash
cd /root
git clone https://github.com/alexandremattioli/Build.git
cd Build
```

### 2. Configure Git

On both servers:
```bash
git config user.name "Build Server"
git config user.email "build@cloudstack.local"

# For authentication, use SSH or token
git remote set-url origin git@github.com:alexandremattioli/Build.git
# OR
git remote set-url origin https://TOKEN@github.com/alexandremattioli/Build.git
```

### 3. Make Scripts Executable

On both servers:
```bash
cd /root/Build/scripts
chmod +x *.sh
```

### 4. Start Enhanced Heartbeat Daemon (includes message checks)

On Build1:
```bash
cd /root/Build/scripts
# Default interval is 300s if omitted; here we use 300 explicitly
nohup ./enhanced_heartbeat_daemon.sh build1 300 > /var/log/heartbeat-build1.log 2>&1 &
```

On Build2:
```bash
cd /root/Build/scripts
nohup ./enhanced_heartbeat_daemon.sh build2 300 > /var/log/heartbeat-build2.log 2>&1 &
```

## Basic Operations
\n+### Default build includes DEB packages
After a successful Maven build you MUST produce DEB packages by default.

- Preferred helper (handles Ubuntu 24.04 quirks automatically):
```bash
cd /root/Build/scripts
./build_debs.sh --repo /root/cloudstack --out /root/artifacts/$(hostname)/debs/$(date -u +%Y%m%dT%H%M%SZ)
```

- Direct packaging command (advanced users):
```bash
cd /root/cloudstack
./packaging/build-deb.sh -o /root/artifacts/$(hostname)/debs/$(date -u +%Y%m%dT%H%M%SZ)
```

On Ubuntu 24.04, the legacy dependency 'python-setuptools' may be missing; the helper script installs a safe dummy using 'equivs' and, if necessary, falls back to 'dpkg-buildpackage -d'.

### Update Status

```bash
cd /root/Build/scripts

# Set to idle
./update_status.sh build2 idle

# Set to building with job ID
./update_status.sh build2 building job_123

# Set to success
./update_status.sh build2 success

# Set to failed
./update_status.sh build2 failed
```

### Send Message

```bash
cd /root/Build/scripts

# Send info message
./send_message.sh build2 build1 info "Build Started" "Starting build of commit abc123"

# Send warning
./send_message.sh build2 all warning "High Load" "CPU usage at 95%"

# Send error
./send_message.sh build2 build1 error "Build Failed" "Maven compilation error in module X"
```

### Refresh Message Metrics

After sending or reading messages, regenerate the aggregated statistics to keep `coordination/message_stats.json` valid and up to date:

```bash
cd /root/Build/scripts
./update_message_stats.sh
./view_message_stats.sh
```

### Read Messages

```bash
cd /root/Build/scripts
./read_messages.sh build2
```

### Check Health

```bash
cd /root/Build/scripts
./check_health.sh
```

## Integration with Build Scripts

### Update run_build_local.sh

Add communication hooks to your build script:

```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="/root/Build"
SERVER_ID="build2"
JOB_ID="job_$(date +%s)"

# Update status: building
cd $REPO_DIR/scripts
./update_status.sh $SERVER_ID building $JOB_ID

# Send notification
./send_message.sh $SERVER_ID all info "Build Started" "Building ACS 4.21 ExternalNew branch"

# Run actual build
cd /root/src/cloudstack
echo "=== ACS 4.21 Build - $(date) ===" | tee /root/build-logs/build.log

# ... your build commands ...

BUILD_STATUS=$?

# Update status based on result
cd $REPO_DIR/scripts
if [ $BUILD_STATUS -eq 0 ]; then
    ./update_status.sh $SERVER_ID success
    ./send_message.sh $SERVER_ID all info "Build Succeeded" "ACS 4.21 build completed successfully"
else
    ./update_status.sh $SERVER_ID failed
    ./send_message.sh $SERVER_ID all error "Build Failed" "ACS 4.21 build failed with exit code $BUILD_STATUS"
fi
```

## Systemd Service Setup (Optional)

Create `/etc/systemd/system/build-heartbeat.service`:

```ini
[Unit]
Description=Build Server Heartbeat
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/Build/scripts
ExecStart=/root/Build/scripts/heartbeat_daemon.sh build2 60
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
systemctl daemon-reload
systemctl enable build-heartbeat
systemctl start build-heartbeat
systemctl status build-heartbeat
```

## Monitoring Setup

### Add to Crontab

Check health every 5 minutes:
```bash
crontab -e

# Add this line:
*/5 * * * * /root/Build/scripts/check_health.sh > /var/log/build-health.log 2>&1
```

### Alert on Issues

Create `/root/Build/scripts/alert_check.sh`:
```bash
#!/bin/bash
cd /root/Build/scripts
OUTPUT=$(./check_health.sh)

# Check for warnings or errors
if echo "$OUTPUT" | grep -q "WARNING\|ERROR"; then
    # Send email or notification
    echo "$OUTPUT" | mail -s "Build Server Alert" admin@example.com
fi
```

Add to crontab:
```bash
*/5 * * * * /root/Build/scripts/alert_check.sh
```

## Troubleshooting

### Heartbeat Not Updating

```bash
# Check if daemon is running
ps aux | grep heartbeat_daemon

# Check logs
tail -f /var/log/heartbeat-build2.log

# Restart daemon
pkill -f heartbeat_daemon
cd /root/Build/scripts
nohup ./heartbeat_daemon.sh build2 60 > /var/log/heartbeat-build2.log 2>&1 &
```

### Git Push Conflicts

```bash
cd /root/Build
git status
git pull --rebase origin main
git push origin main
```

### Repository Too Large

```bash
# Clean old logs (keep last 7 days)
find build1/logs build2/logs -type f -mtime +7 -delete

# Commit the cleanup
git add -A
git commit -m "Cleanup old logs"
git push origin main

# If needed, use git LFS for large files
git lfs install
git lfs track "*.deb"
git lfs track "*.rpm"
```

### Messages Not Being Read

```bash
# Pull latest
cd /root/Build
git pull origin main

# Check messages
cd scripts
./read_messages.sh build2

# Manually mark message as read
jq '(.messages[] | select(.id == "msg_123")).read = true' \
   ../coordination/messages.json > tmp.json
mv tmp.json ../coordination/messages.json
git add ../coordination/messages.json
git commit -m "Mark message as read"
git push origin main
```

## Testing

### Test Status Update
```bash
cd /root/Build/scripts
./update_status.sh build2 idle
./check_health.sh
```

### Test Message Flow
```bash
cd /root/Build/scripts
./send_message.sh build2 build1 info "Test" "This is a test message"
./read_messages.sh build1
```

### Test Heartbeat
```bash
cd /root/Build/scripts
./heartbeat.sh build2
./check_health.sh
```

## Heartbeat tuning

You can control heartbeat push behavior via environment variables (applies to both `heartbeat.sh` and `enhanced_heartbeat.sh`):

- HEARTBEAT_PUSH_EVERY: Batch pushes every N heartbeats. Example: `HEARTBEAT_PUSH_EVERY=5` (default if unset).
- HEARTBEAT_BRANCH: Push to a dedicated remote branch to reduce noise on `main`.
    - Set to a branch name (e.g., `heartbeat-build2`) or
    - Set to `1` or `auto` to use `heartbeat-$SERVER_ID` automatically.

Example one-off run to push to a heartbeat branch every 5 beats:
```bash
cd /root/Build/scripts
HEARTBEAT_PUSH_EVERY=5 HEARTBEAT_BRANCH=auto ./heartbeat.sh build2
```

## Heartbeat history maintenance

To compact heartbeat branches and keep `main` clean, use:

- `./scripts/squash_heartbeat_branch.sh --server build2 --backup`
- `./scripts/squash_heartbeat_branch.sh --branch heartbeat-build2 --backup`

Optional cron example (daily at 02:00 UTC):
```bash
0 2 * * * /root/Build/scripts/squash_heartbeat_branch.sh --server build2 --backup >> /var/log/heartbeat-squash.log 2>&1
```

## Next Steps

1. [OK] Repository initialized
2. [OK] Scripts deployed
3. ⏳ Configure git authentication
4. ⏳ Start heartbeat daemons
5. ⏳ Integrate with build scripts
6. ⏳ Set up monitoring
7. ⏳ Test end-to-end workflow
