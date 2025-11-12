#!/bin/bash
#
# Notify Build2 to check for new messages
# Triggers Build2's message reading system via SSH
#
# Usage: 
#   ./scripts/notify_build2.sh [build2-ip]
#
# If IP not provided, uses default

set -e

BUILD2_IP="${1:-10.1.3.177}"  # Build2's documented IP address
BUILD2_HOST="root@$BUILD2_IP"
BUILD2_BUILD_DIR="/Builder2/Build"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD1_LOG="/root/Build/logs/notify_build2.log"
BUILD2_LOG="$BUILD2_BUILD_DIR/logs/notify_received.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$BUILD1_LOG")"

# Log on Build1 (source)
echo "[$TIMESTAMP] Notifying Build2 at $BUILD2_IP (initiated from Build1)" >> "$BUILD1_LOG"
echo "Attempting to notify Build2 at $BUILD2_IP..."
echo ""

# Test connectivity first
if ! ping -c 1 -W 2 "$BUILD2_IP" &>/dev/null; then
    echo "[X] Cannot reach Build2 at $BUILD2_IP"
    echo "[$TIMESTAMP] FAILED: Cannot reach Build2 at $BUILD2_IP" >> "$BUILD1_LOG"
    echo ""
    echo "Please provide Build2's IP address:"
    echo "  ./scripts/notify_build2.sh <build2-ip>"
    exit 1
fi

echo "[OK] Build2 is reachable at $BUILD2_IP"

# Create log directory on Build2 if needed
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "mkdir -p $BUILD2_BUILD_DIR/logs" 2>/dev/null || true

# Log on Build2 (destination)
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "echo '[$TIMESTAMP] Notification received from Build1 (10.1.3.175)' >> $BUILD2_LOG" 2>/dev/null || true

# Method 1: Pull latest messages
echo "Triggering git pull on Build2..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "cd $BUILD2_BUILD_DIR && git pull --rebase origin main --quiet" 2>/dev/null || echo "  (git pull may have failed)"

# Method 2: Run read_messages.sh directly
echo "Running read_messages.sh on Build2..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "cd $BUILD2_BUILD_DIR && bash scripts/read_messages.sh build2 2>/dev/null | grep -A 20 'Unread Messages' || echo '  No unread messages found'"

# Method 3: Check if there's an auto-responder running
echo "Checking for auto-responder on Build2..."
AUTO_RESPONDER_PID=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "pgrep -f 'auto_respond' || echo '0'")

if [ "$AUTO_RESPONDER_PID" != "0" ]; then
    echo "  Auto-responder is running (PID: $AUTO_RESPONDER_PID)"
    echo "  Sending SIGUSR1 to trigger immediate check..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
        "kill -USR1 $AUTO_RESPONDER_PID 2>/dev/null && echo '  Signal sent successfully' || echo '  Signal failed'"
else
    echo "  No auto-responder running"
fi

# Method 4: Create a notification file that VS Code can detect
echo "Creating notification marker for VS Code..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "echo '[$TIMESTAMP] New messages from Build1 - CHECK MESSAGES!' > $BUILD2_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo 'Subject: ALERT - New Messages from Build1' >> $BUILD2_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo 'Priority: HIGH' >> $BUILD2_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo 'Action Required: Run read_messages.sh or check messages/' >> $BUILD2_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo '' >> $BUILD2_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     ls -1t $BUILD2_BUILD_DIR/messages/*.txt 2>/dev/null | head -5 >> $BUILD2_BUILD_DIR/.NEW_MESSAGES_ALERT || true"
echo "  [OK] Created .NEW_MESSAGES_ALERT file (visible in VS Code)"

# Method 5: Send terminal bell/notification if interactive terminal exists
echo "Attempting to send terminal notification..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD2_HOST" \
    "for tty in /dev/pts/*; do [ -w \$tty ] && echo -e '\a\n*** NEW MESSAGES FROM BUILD1 ***\n' > \$tty 2>/dev/null || true; done"
echo "  [OK] Terminal notifications sent (if any active terminals)"

echo ""
echo "[OK] Build2 notified successfully!"
echo "[$TIMESTAMP] SUCCESS: Build2 notified successfully" >> "$BUILD1_LOG"
echo ""
echo "Logs:"
echo "  Build1: $BUILD1_LOG"
echo "  Build2: $BUILD2_LOG (on remote)"
