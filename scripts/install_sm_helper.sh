#!/bin/bash
# install_sm_helper.sh - installs the sm messaging wrapper in /usr/local/bin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEND_SCRIPT="$BUILD_ROOT/scripts/send_message.sh"
TARGET="/usr/local/bin/sm"

if [ ! -f "$SEND_SCRIPT" ]; then
    echo "install_sm_helper: missing $SEND_SCRIPT" >&2
    exit 1
fi

cat <<EOF >"$TARGET"
#!/bin/bash
# Wrapper so 'sm' works from any directory.
set -euo pipefail

BUILD_ROOT="$BUILD_ROOT"
SEND_SCRIPT="\$BUILD_ROOT/scripts/send_message.sh"

if [ "\$#" -lt 5 ]; then
  printf '%s\n' \
    'Usage: sm <from> <to> <type> "<subject>" "<body>" [--require-ack]' \
    'Example: sm build1 all info "Daily Sync" "All tasks green; next update 16:00Z"' >&2
  exit 1
fi

if [ ! -x "\$SEND_SCRIPT" ]; then
  echo "sm error: cannot find executable \$SEND_SCRIPT" >&2
  exit 1
fi

cd "\$BUILD_ROOT"
exec "\$SEND_SCRIPT" "\$@"
EOF

chmod +x "$TARGET"
echo "✓ Installed sm helper at $TARGET"
