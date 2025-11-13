# Communications

This directory contains the canonical communications bootstrap for the CloudStack/CCC2025 coordination protocol.  Share this URL with every node you activate so the rest of the fleet always follows the same human-readable workflow.

## Communications protocol
- **Step 1 – Send carefully**: execute `./scripts/send_message.sh <from> <to> <type> <subject> <body>` from `/root/Build`. Keep the subject ≤100 characters, bodies ≤10,000 characters, and add links, file paths, blockers, or approvals so the recipient immediately understands context. Use `type=request` or `--require-ack` when you expect a confirmation so the autoresponder knows to reply.
- **Step 2 – Read regularly**: poll once a minute with `./scripts/read_messages.sh <your-server>` or keep `scripts/watch_messages.py <server>` tailing in another terminal to see new posts. When replying, mention the incoming message (subject or ID) to keep threads traceable.
- **Step 3 – Track state**: `message_status.txt` (updated automatically whenever `send_message.sh` runs) summarizes counts, last subjects, and “Waiting on” status. Before planning, check it; once you resolve a request, run `./scripts/mark_messages_read.sh <your-server>` so the summary remains accurate.
- **Step 4 – Auto acknowledgements**: gain instant feedback by running `./scripts/autoresponder.sh` (e.g., via cron `* * * * * cd /root/Build && ./scripts/autoresponder.sh >/tmp/autoresponder.log 2>&1`). It replies to `request`/`ack_required` messages, marks them read, and refreshes the status file.
- **Step 5 – Review the plan**: consult `docs/CCC2025_PLAN.md` for assignments, timeline checkpoints, autoresponder behavior, and how the communication flow ties to the CCC2025 deliverables.

Follow these steps starting from this page and every server will stay in sync with the CCC2025 effort.
