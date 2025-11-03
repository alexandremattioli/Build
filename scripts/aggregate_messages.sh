#!/usr/bin/env bash
set -euo pipefail

# Aggregate message metadata and content from messages/ into root files:
# - MESSAGES_STATUS.md: summary table with key fields per message
# - MESSAGES_ALL.txt: concatenated full message contents with separators

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MSG_DIR="$ROOT_DIR/messages"
COORD_FILE="$ROOT_DIR/coordination/messages.json"
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
  echo "Text message files: $total"
  if [[ -f "$COORD_FILE" ]]; then
    coord_total=$(jq '.messages | length' "$COORD_FILE")
    echo "Coordination messages: $coord_total"
  fi
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

  if [[ -f "$COORD_FILE" ]]; then
    echo
    echo "## Coordination Thread (coordination/messages.json)"
    echo
    coord_total=${coord_total:-$(jq '.messages | length' "$COORD_FILE")}
    unread_build1=$(jq '[.messages[] | select((.to == "build1" or .to == "all") and (.read != true))] | length' "$COORD_FILE")
    unread_build2=$(jq '[.messages[] | select((.to == "build2" or .to == "all") and (.read != true))] | length' "$COORD_FILE")
    unread_build3=$(jq '[.messages[] | select((.to == "build3" or .to == "all") and (.read != true))] | length' "$COORD_FILE")
    unread_build4=$(jq '[.messages[] | select((.to == "build4" or .to == "all") and (.read != true))] | length' "$COORD_FILE")
    echo "Total messages: $coord_total"
    echo "Unread: build1=$unread_build1 build2=$unread_build2 build3=$unread_build3 build4=$unread_build4"
    echo
    echo "| ID | FROM | TO | TYPE | PRIORITY | TIMESTAMP | SUBJECT | READ |"
    echo "|----|------|----|------|----------|-----------|---------|------|"
    jq -r '
      .messages
      | sort_by(.timestamp)
      | .[]
      | [
          .id,
          .from,
          .to,
          .type,
          (.priority // "normal"),
          (.timestamp // ""),
          (.subject // ""),
          (if .read == true then "yes" else "no" end)
        ]
      | @tsv
    ' "$COORD_FILE" | while IFS=$'\t' read -r id from to type priority ts subject read; do
      subject_escaped=${subject//|/\\|}
      echo "| ${id:-} | ${from:-} | ${to:-} | ${type:-} | ${priority:-} | ${ts:-} | ${subject_escaped:-} | ${read:-} |"
    done
  fi
} > "$STATUS_FILE"

# Build concatenated full messages
{
  echo "===== ALL MESSAGES (Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC) ====="
  echo
  echo "--- TEXT FILES (messages/*.txt) ---"
  echo
  while IFS= read -r -d '' f; do
    echo "----- FILE: $(basename "$f") -----"
    cat "$f"
    echo
  done < <(find "$MSG_DIR" -maxdepth 1 -type f -name "*.txt" -print0 | sort -z)

  if [[ -f "$COORD_FILE" ]]; then
    echo "--- COORDINATION THREAD (coordination/messages.json) ---"
    echo
    jq -r '
      .messages
      | sort_by(.timestamp)
      | .[]
      | [
          "----- MESSAGE: " + (.id // "unknown") + " -----",
          "FROM: " + (.from // ""),
          "TO: " + (.to // ""),
          "TYPE: " + (.type // ""),
          "PRIORITY: " + (.priority // "normal"),
          "TIMESTAMP: " + (.timestamp // ""),
          "READ: " + (if .read == true then "yes" else "no" end),
          "",
          "SUBJECT: " + (.subject // ""),
          "",
          (if (.body // "") == "" then "BODY: (empty)" else "BODY:\n" + (.body // "") end),
          ""
        ]
      | join("\n")
    ' "$COORD_FILE"
  fi
} > "$ALL_FILE"

echo "Wrote:" >&2
echo "  $STATUS_FILE" >&2
echo "  $ALL_FILE" >&2
