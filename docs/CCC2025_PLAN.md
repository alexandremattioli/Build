# CCC2025 Presentation Plan

The coordination message set the agenda for our CCC2025 work. Here is what Build1 is owning and how the broader coordination flow works:

## What Build1 Delivers
1. **Lab environment and MikroTik configs**
   * Document the topology, IP plan, and router roles (Core AS64500, Edge-A AS64510, Edge-B AS64520) so the demo runs reliably.
   * Capture the MikroTik v7 CLI commands for configuring interfaces, BGP peers, and policy knobs (local-pref, MED, AS-path prepend).
   * Spell out the BFD configuration, timer settings, and what “failover within <3s” means in observable terms.
2. **Reusable runbook/snippets**
   * Aggregate the router configuration snippets, failover automation steps, and BFD tuning notes into a single runbook/wiki page.
   * Include copy‑paste ready commands for the demo timeline (preflight checks → failover trigger → verification).
3. **Sync points**
   * Coordinate with Build2 on the CloudStack 4.21 Routed Mode + Dynamic Routing guide so the network config steps align.
   * Align with Code2 on slide assets/notes; let me know if you want me to draft partial slides or script templates.

## How the messaging workflow works
* We keep using `./scripts/send_message.sh` / `./scripts/read_messages.sh` in `/root/Build` to broadcast and pick up updates (polling every minute).
* Every message automatically runs `scripts/update_message_status_txt.sh` to refresh `message_status.txt` so others can see counts/last subjects.
* If you open a terminal, `watch_messages.py build1` will tail new entries; otherwise the cron or manual read keeps the inbox fresh.

## Autoresponder helper
Run `./scripts/autoresponder.sh` via cron (e.g., `* * * * * cd /root/Build && ./scripts/autoresponder.sh >/tmp/autoresponder.log 2>&1`) so the fleet automatically acknowledges `request`-type or `ack_required` messages as soon as they arrive. The script reads your local server ID, tracks which messages it already replied to, marks them read, and logs the status via `message_status.txt` so nothing slips through the cracks.

## Communication guide
1. **Send carefully**
   * Use `./scripts/send_message.sh <from> <to> <type> <subject> <body>` to broadcast updates (subject <=100 chars, body <=10k). When referring to CCC2025 work, please include links/paths and highlight blockers or required approvals.
   * For quick pings (`build1` → `build2`), choose `type=request` so the autoresponder replies with an ACK.
2. **Read regularly**
   * Run `./scripts/read_messages.sh <your-server>` once per minute, or keep `scripts/watch_messages.py <server>` tailing in a second terminal for live updates.
   * If you see a `Master` or `Code2` update, respond with a new message referencing the original ID so the audit trail stays complete.
3. **State tracking**
   * The `message_status.txt` summary rewrites after each send (the hook we added). Check it (or `docs/MESSAGES_STATUS.md`) before planning to see unread counts and last subject.
   * When you handle a request (manual or auto), mark it read via `./scripts/mark_messages_read.sh <server>` to keep the waiting-on status accurate.

Keep this guidance handy whenever you coordinate between Build1/Build2/Code2 so nothing slips through during CCC2025 prep.

## Next actions
1. Build1: start drafting the lab doc + MikroTik/BGP/BFD sections in `docs/` or the CCC2025 repo, link to them in future messages, and share CLI snippets as soon as they’re ready.
2. Build2: post quick updates when new Routed Mode docs are ready so I can integrate references or call-outs.
3. Code2: drop slide drafts or callouts into messages so we can align the runbook bullets with the presentation flow.

Any blockers, post them via `send_message.sh build1 all ...` and I’ll respond within the minute. Let me know when you want help turning the runbook into slides or adding diagrams.
