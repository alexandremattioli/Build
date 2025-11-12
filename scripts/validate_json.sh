#!/bin/bash
# validate_json.sh - Validate JSON files against schemas
# Usage: ./validate_json.sh <file>

set -euo pipefail

FILE="$1"

if ! jq empty "$FILE" 2>/dev/null; then
    echo "ERROR: Invalid JSON in $FILE" >&2
    exit 1
fi

case "$FILE" in
    */status.json)
        jq -e '.server and .ip and .status and .timestamp' "$FILE" >/dev/null || {
            echo "ERROR: Missing required fields in $FILE" >&2
            exit 1
        }
        ;;
    */messages.json)
        jq -e '.messages | type == "array"' "$FILE" >/dev/null || {
            echo "ERROR: messages must be an array in $FILE" >&2
            exit 1
        }
        ;;
    */jobs.json)
        jq -e '.jobs | type == "array"' "$FILE" >/dev/null || {
            echo "ERROR: jobs must be an array in $FILE" >&2
            exit 1
        }
        ;;
    */locks.json)
        jq -e '.locks | type == "object"' "$FILE" >/dev/null || {
            echo "ERROR: locks must be an object in $FILE" >&2
            exit 1
        }
        ;;
    */build_config.json)
        jq -e '. | type == "object"' "$FILE" >/dev/null || {
            echo "ERROR: build_config must be an object in $FILE" >&2
            exit 1
        }
        ;;
    */health_dashboard.json)
        jq -e '. | type == "object"' "$FILE" >/dev/null || {
            echo "ERROR: health_dashboard must be an object in $FILE" >&2
            exit 1
        }
        ;;
    *)
        # No extra schema checks
        ;;
esac

echo "[OK] $FILE is valid"
