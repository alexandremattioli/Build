#!/usr/bin/env bash
set -euo pipefail
# scripts/server_id.sh - determine and print the current server identity (build1|build2)
# Precedence:
#  1) $SERVER_ID environment variable (explicit override)
#  2) /etc/build_server_id (system-wide, untracked)
#  3) ./.build_server_id in this repo (local marker; recommended to keep untracked)
#  4) Hostname/IP heuristic
#  5) Fallback: print "unknown" and exit 1

if [[ "${SERVER_ID:-}" != "" ]]; then
  printf "%s\n" "$SERVER_ID"
  exit 0
fi

if [[ -f "/etc/build_server_id" ]]; then
  id=$(tr -d '\r\n' < /etc/build_server_id)
  if [[ "$id" != "" ]]; then printf "%s\n" "$id"; exit 0; fi
fi

if [[ -f "$(dirname "$0")/../.build_server_id" ]]; then
  id=$(tr -d '\r\n' < "$(dirname "$0")/../.build_server_id")
  if [[ "$id" != "" ]]; then printf "%s\n" "$id"; exit 0; fi
fi

hn=$(hostname 2>/dev/null || true)
ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
case "$hn|$ip" in
  *ll-ACSBuilder1*|*10.1.3.175*) printf "%s\n" "build1"; exit 0;;
  *ll-ACSBuilder2*|*10.1.3.177*) printf "%s\n" "build2"; exit 0;;
  *) :;;
endsac

printf "%s\n" "unknown" >&2
exit 1
