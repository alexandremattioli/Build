#!/bin/bash
#
# Notify Build1 to check for new messages
# Triggers Build1's message reading system via SSH
#
# Usage: 
#   ./scripts/notify_build1.sh [build1-ip]
#
# If IP not provided, attempts common options

set -e

BUILD1_IP="${1:-10.1.3.175}"  # Build1's documented IP address
BUILD1_HOST="root@$BUILD1_IP"
BUILD1_BUILD_DIR="/root/Build"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD2_LOG="/Builder2/Build/logs/notify_build1.log"
BUILD1_LOG="$BUILD1_BUILD_DIR/logs/notify_received.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$BUILD2_LOG")"

# Log on Build2 (source)
echo "[$TIMESTAMP] Notifying Build1 at $BUILD1_IP (initiated from Build2)" >> "$BUILD2_LOG"

echo "Attempting to notify Build1 at $BUILD1_IP..."
echo ""

# Test connectivity first
if ! ping -c 1 -W 2 "$BUILD1_IP" &>/dev/null; then
    echo "[X] Cannot reach Build1 at $BUILD1_IP"
    echo "[$TIMESTAMP] FAILED: Cannot reach Build1 at $BUILD1_IP" >> "$BUILD2_LOG"
    echo ""
    echo "Please provide Build1's IP address:"
    echo "  ./scripts/notify_build1.sh <build1-ip>"
    echo ""
    echo "Or add Build1 to /etc/hosts:"
    echo "  echo '<build1-ip>  ll-ACSBuilder1' >> /etc/hosts"
    exit 1
fi

echo "[OK] Build1 is reachable at $BUILD1_IP"

# Create log directory on Build1 if needed
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "mkdir -p $BUILD1_BUILD_DIR/logs" 2>/dev/null || true

# Log on Build1 (destination)
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "echo '[$TIMESTAMP] Notification received from Build2 (10.1.3.177)' >> $BUILD1_LOG" 2>/dev/null || true

# Method 1: Pull latest messages
echo "Triggering git pull on Build1..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "cd $BUILD1_BUILD_DIR && git pull --rebase origin main --quiet" 2>/dev/null || echo "  (git pull may have failed)"

# Method 2: Run read_messages.sh directly
echo "Running read_messages.sh on Build1..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "cd $BUILD1_BUILD_DIR && bash scripts/read_messages.sh build1 2>/dev/null | grep -A 20 'Unread Messages' || echo '  No unread messages found'" 

# Method 3: Check if there's an auto-responder running
echo "Checking for auto-responder on Build1..."
AUTO_RESPONDER_PID=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "pgrep -f 'auto_respond' || echo '0'")

if [ "$AUTO_RESPONDER_PID" != "0" ]; then
    echo "  Auto-responder is running (PID: $AUTO_RESPONDER_PID)"
    echo "  Sending SIGUSR1 to trigger immediate check..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
        "kill -USR1 $AUTO_RESPONDER_PID 2>/dev/null && echo '  Signal sent successfully' || echo '  Signal failed'"
else
    echo "  No auto-responder running"
fi

# Method 4: Create a notification file that VS Code can detect
echo "Creating notification marker for VS Code..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "echo '[$TIMESTAMP] New messages from Build2 - CHECK MESSAGES!' > $BUILD1_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo 'Subject: ALERT - New Messages from Build2' >> $BUILD1_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo 'Priority: HIGH' >> $BUILD1_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo 'Action Required: Run read_messages.sh or check messages/' >> $BUILD1_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     echo '' >> $BUILD1_BUILD_DIR/.NEW_MESSAGES_ALERT && \
     ls -1t $BUILD1_BUILD_DIR/messages/*.txt 2>/dev/null | head -5 >> $BUILD1_BUILD_DIR/.NEW_MESSAGES_ALERT || true"
echo "  [OK] Created .NEW_MESSAGES_ALERT file (visible in VS Code)"

# Method 5: Send terminal bell/notification if interactive terminal exists
echo "Attempting to send terminal notification..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$BUILD1_HOST" \
    "for tty in /dev/pts/*; do [ -w \$tty ] && echo -e '\a\n*** NEW MESSAGES FROM BUILD2 ***\n' > \$tty 2>/dev/null || true; done"
echo "  [OK] Terminal notifications sent (if any active terminals)"

echo ""
echo "[OK] Build1 notified successfully!"
echo "[$TIMESTAMP] SUCCESS: Build1 notified successfully" >> "$BUILD2_LOG"
echo ""
echo "Recent messages for Build1 to read:"
echo "  - work_distribution_policy_20251104.txt (CRITICAL)"
echo "  - vnf_status_and_responses_20251104.txt"
echo "  - time_estimates_guidance_20251104.txt"
echo "  - auto_responder_notification_20251104.txt"
echo ""
echo "Logs:"
echo "  Build2: $BUILD2_LOG"
echo "  Build1: $BUILD1_LOG (on remote)"
