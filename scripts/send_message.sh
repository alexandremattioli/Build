#!/bin/bash
# send_message.sh - Send a message to another server
# Usage: ./send_message.sh <from> <to> <type> <subject> <body>

set -euo pipefail

FROM_SERVER="$1"
TO_SERVER="$2"
MSG_TYPE="$3"
SUBJECT="$4"
BODY="$5"

REPO_DIR="/root/Build"
cd "$REPO_DIR"

# Generate UUID
MSG_ID="msg_$(date +%s)_$(shuf -i 1000-9999 -n 1)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Pull latest
git pull origin main --rebase --autostash

# Add message
jq --arg id "$MSG_ID" \
   --arg from "$FROM_SERVER" \
   --arg to "$TO_SERVER" \
   --arg type "$MSG_TYPE" \
   --arg subject "$SUBJECT" \
   --arg body "$BODY" \
   --arg ts "$TIMESTAMP" \
   '.messages += [{
       id: $id,
       from: $from,
       to: $to,
       type: $type,
       subject: $subject,
       body: $body,
       timestamp: $ts,
       read: false
   }]' coordination/messages.json > tmp.json

mv tmp.json coordination/messages.json

# Commit and push
git add coordination/messages.json
git commit -m "Message from $FROM_SERVER to $TO_SERVER: $SUBJECT"
git push origin main

echo "Message sent: $MSG_ID"

# Update statistics
cd scripts
./update_message_stats.sh >/dev/null 2>&1 || true
