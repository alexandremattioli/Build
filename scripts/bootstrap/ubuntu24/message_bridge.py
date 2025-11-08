#!/usr/bin/env python3
import os, subprocess, json

LEGACY_SEND = '/Builder2/Build/scripts/send_message.sh'
LEGACY_ALIAS = '/usr/local/bin/sendmessages'


def bridge(event: str, data: dict):
    payload = json.dumps(data)
    if os.path.exists(LEGACY_SEND):
        try:
            subprocess.run([LEGACY_SEND, 'all', f"Hive {event}", payload], check=False)
        except Exception:
            pass
    elif os.path.exists(LEGACY_ALIAS):
        try:
            subprocess.run([LEGACY_ALIAS, 'all', f"Hive {event}", payload], check=False)
        except Exception:
            pass

if __name__ == '__main__':
    import sys
    evt = sys.argv[1] if len(sys.argv) > 1 else 'event'
    dat = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    bridge(evt, dat)
