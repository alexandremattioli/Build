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

### 4. Start Heartbeat Daemon

On Build1:
```bash
cd /root/Build/scripts
nohup ./heartbeat_daemon.sh build1 60 > /var/log/heartbeat.log 2>&1 &
```

On Build2:
```bash
cd /root/Build/scripts
nohup ./heartbeat_daemon.sh build2 60 > /var/log/heartbeat.log 2>&1 &
```

## Basic Operations

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
tail -f /var/log/heartbeat.log

# Restart daemon
pkill -f heartbeat_daemon
cd /root/Build/scripts
nohup ./heartbeat_daemon.sh build2 60 > /var/log/heartbeat.log 2>&1 &
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

## Next Steps

1. ✅ Repository initialized
2. ✅ Scripts deployed
3. ⏳ Configure git authentication
4. ⏳ Start heartbeat daemons
5. ⏳ Integrate with build scripts
6. ⏳ Set up monitoring
7. ⏳ Test end-to-end workflow
