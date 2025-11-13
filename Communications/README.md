# Communications

This directory contains the canonical communications bootstrap for every build server in the fleet. Share this URL with any node you activate so the entire team follows the same human-readable workflow, regardless of project.

## Communications protocol
- **Step 1 – Send carefully**: execute `./scripts/send_message.sh <from> <to> <type> <subject> <body>` from `/root/Build`. Keep the subject ≤100 characters, bodies ≤10,000 characters, and add links, file paths, blockers, or approvals so the recipient immediately understands context. Use `type=request` or `--require-ack` when you expect a confirmation so the autoresponder knows to reply. After sending, confirm the commit succeeded and run `./scripts/read_messages.sh <your-server>` once to verify the entry landed in `coordination/messages.json`.
- **Step 2 – Read regularly**: poll once a minute with `./scripts/read_messages.sh <your-server>` or keep `scripts/watch_messages.py <server>` tailing in another terminal to see new posts. When replying, mention the incoming message (subject or ID) to keep threads traceable.
- **Step 3 – Track state**: `message_status.txt` (https://github.com/alexandremattioli/Build/blob/main/message_status.txt) is updated automatically whenever `send_message.sh` runs and summarizes counts, last subjects, and “Waiting on” status. Before planning, check it; once you resolve a request, run `./scripts/mark_messages_read.sh <your-server>` so the summary remains accurate.
- **Step 4 – Auto acknowledgements**: gain instant feedback by running `./scripts/autoresponder.sh` (e.g., via cron `* * * * * cd /root/Build && ./scripts/autoresponder.sh >/tmp/autoresponder.log 2>&1`). It replies to `request`/`ack_required` messages, marks them read, and refreshes the status file.
- **Step 5 – Project context**: when a specific initiative (e.g., CCC2025) is in flight, consult the relevant docs (such as `docs/CCC2025_PLAN.md`) for assignments, schedules, and deliverables. The messaging habits above remain constant across projects.

Follow these steps starting from this page and every server will stay in sync with the rest of the fleet.
