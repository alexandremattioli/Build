# Communications

This directory collects reference material for the CloudStack/CCC2025 coordination protocol.  All servers must follow the communication guide below.

## Communications protocol
- **Send carefully**: run `./scripts/send_message.sh <from> <to> <type> <subject> <body>` (subject ≤100 chars, body ≤10k). Choose `type=request` or set `ack_required` when you need an acknowledgement and include links, paths, blockers, or approvals in the body.
- **Read regularly**: poll every minute with `./scripts/read_messages.sh <your-server>` or keep `scripts/watch_messages.py <server>` tailing for live updates; always reference the original message when replying so threads stay clear.
- **Track state**: `message_status.txt` auto-updates after each send; check it to see unread counts and last subject. After replying manually, mark messages read with `./scripts/mark_messages_read.sh <your-server>` so the “Waiting on…” status stays accurate.

See `docs/CCC2025_PLAN.md` for the broader CCC2025 plan, agenda, and autoresponder instructions.
