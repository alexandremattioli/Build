#!/bin/bash
# collect_metrics.sh - Collect and store performance metrics
# Usage: ./collect_metrics.sh

set -euo pipefail

REPO_DIR="/root/Build"
cd "$REPO_DIR"

METRICS_FILE="shared/metrics.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TOTAL_MESSAGES=$(jq '.messages | length' coordination/messages.json)
UNREAD_MESSAGES=$(jq '[.messages[] | select(.read == false)] | length' coordination/messages.json)
TOTAL_JOBS=$(jq '.jobs | length' coordination/jobs.json)
REPO_SIZE=$(du -sb . | cut -f1)
COMMIT_COUNT=$(git rev-list --count HEAD)

if [ ! -f "$METRICS_FILE" ]; then
    echo '{"metrics":[]}' > "$METRICS_FILE"
fi

jq --arg ts "$TIMESTAMP" \
   --argjson total_msg "$TOTAL_MESSAGES" \
   --argjson unread_msg "$UNREAD_MESSAGES" \
   --argjson total_jobs "$TOTAL_JOBS" \
   --argjson repo_size "$REPO_SIZE" \
   --argjson commits "$COMMIT_COUNT" \
   '.metrics += [{
       timestamp: $ts,
       messages: {total: $total_msg, unread: $unread_msg},
       jobs: {total: $total_jobs},
       repository: {size_bytes: $repo_size, commits: $commits}
   }]' "$METRICS_FILE" > tmp.json

mv tmp.json "$METRICS_FILE"

echo "Metrics collected at $TIMESTAMP"
