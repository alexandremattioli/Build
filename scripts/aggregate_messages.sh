#!/usr/bin/env bash
set -euo pipefail

# Aggregate message metadata and content from messages/ into root files:
# - MESSAGES_STATUS.md: summary table with key fields per message
# - MESSAGES_ALL.txt: concatenated full message contents with separators

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MSG_DIR="$ROOT_DIR/messages"
STATUS_FILE="$ROOT_DIR/MESSAGES_STATUS.md"
ALL_FILE="$ROOT_DIR/MESSAGES_ALL.txt"

if [[ ! -d "$MSG_DIR" ]]; then
  echo "messages directory not found: $MSG_DIR" >&2
  exit 1
fi

# Helper to extract a field (case-insensitive) from a message file
extract_field() {
  local file="$1"; shift
  local key="$1"; shift
  # Use grep -i for case-insensitive, take first match, strip 'Key: ' prefix and trim
  grep -i -m1 -E "^${key}:[[:space:]]*" "$file" | sed -E "s/^${key}:[[:space:]]*//I" | tr -d '\r'
}

# Build status markdown header
{
  echo "# Messages Status"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC)"
  echo
  total=$(find "$MSG_DIR" -maxdepth 1 -type f -name "*.txt" | wc -l | tr -d ' ')
  echo "Total messages: $total"
  echo
  echo "| File | TO | FROM | PRIORITY | TYPE | TIMESTAMP | SUBJECT |"
  echo "|------|----|------|----------|------|-----------|---------|"

  # Iterate deterministically by name
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    to=$(extract_field "$f" "TO" || true)
    from=$(extract_field "$f" "FROM" || true)
    prio=$(extract_field "$f" "PRIORITY" || true)
    type=$(extract_field "$f" "TYPE" || true)
    ts=$(extract_field "$f" "TIMESTAMP" || true)
    subj=$(extract_field "$f" "SUBJECT" || true)
    # Escape pipes in subject
    subj=${subj//|/\|}
    echo "| $base | ${to:-} | ${from:-} | ${prio:-} | ${type:-} | ${ts:-} | ${subj:-} |"
  done < <(find "$MSG_DIR" -maxdepth 1 -type f -name "*.txt" -print0 | sort -z)
} > "$STATUS_FILE"

# Build concatenated full messages
{
  echo "===== ALL MESSAGES (Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC) ====="
  echo
  while IFS= read -r -d '' f; do
    echo "----- FILE: $(basename "$f") -----"
    cat "$f"
    echo
  done < <(find "$MSG_DIR" -maxdepth 1 -type f -name "*.txt" -print0 | sort -z)
} > "$ALL_FILE"

echo "Wrote:" >&2
echo "  $STATUS_FILE" >&2
echo "  $ALL_FILE" >&2
