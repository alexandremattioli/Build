# Hive Legacy Messaging Bridge

This bridge lets the hive broadcast key events to existing messaging scripts so teams depending on legacy notifications still see updates during the migration.

## What it does
- On important hive events (discovery, identity assignment, package install outcome), the agent invokes a small bridge helper.
- The bridge calls one of the following if present (first match wins):
  - `/Builder2/Build/scripts/send_message.sh`
  - `/usr/local/bin/sendmessages`
- Messages are formatted as: target `all`, title `Hive <event>`, body containing a compact JSON payload.

## Events currently bridged
- `node_discovered` — when the agent refreshes its peer view
- `identity_assigned` — after consensus picks a role for the node
- `packages_installed` — when role packages install successfully
- `package_install_failed` — if packages fail to install
- `founder` — when this is the first node in a hive

## Files
- `scripts/bootstrap/ubuntu24/message_bridge.py` — lightweight bridge helper
- `scripts/bootstrap/ubuntu24/peer_agent.py` — calls the bridge on each event
- `scripts/bootstrap/ubuntu24/install.sh` — deploys the bridge alongside the agent

## Operational notes
- If neither legacy script exists, the bridge does nothing and exits cleanly.
- The agent does not block on bridge failures; it treats them as best-effort.
- You can add your own adapter by creating `/usr/local/bin/sendmessages` with a compatible interface:

```bash
#!/usr/bin/env bash
# Usage: sendmessages <target> <title> <body>
# Example: sendmessages all "Hive identity_assigned" '{"hostname":"build3","role":"builder"}'

target="$1"; title="$2"; body="$3"
# Example implementation: log and forward to Slack/Webhook/etc.
echo "[$(date -Iseconds)] $target | $title | $body" >> /var/log/hive-bridge.log
# curl -X POST ... "$body"
```

## Disable or customize
- To disable bridging, remove or rename the legacy script(s) so the bridge finds nothing.
- To customize, point `/usr/local/bin/sendmessages` to your desired transport (Slack, Teams, email, MQTT, etc.).
