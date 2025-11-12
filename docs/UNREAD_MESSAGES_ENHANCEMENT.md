# Unread Message Tracking and Conversation Thread - Enhancement Summary

**Date**: October 31, 2025  
**Version**: 2.0  
**Author**: Build2 (GitHub Copilot)

## Overview

This document describes the new unread message tracking system and conversation thread reading capabilities added to the Build Server Coordination Repository.

## New Features

### 1. Unread Message Status Tracking

**File**: `coordination/unread_messages_status.json`

This file tracks unread message counts and status for all build servers, updated automatically by the new checking scripts.

**Structure**:
```json
{
  "last_checked": "2025-10-31T14:00:00Z",
  "servers": {
    "build1": {
      "unread_count": 15,
      "has_unread": true,
      "first_unread_message": { /* message object */ }
    },
    "build2": {
      "unread_count": 0,
      "has_unread": false,
      "first_unread_message": null
    }
    // ... build3, build4
  }
}
```

### 2. Enhanced message_status.txt Format

**File**: `message_status.txt`

Now includes comprehensive information with the following format:

```
Line 1: Build1 messages: N  Last message: YYYY-MM-DD HH:MM
Line 2: Build2 messages: N  Last message: YYYY-MM-DD HH:MM
Line 3: Last message from: X to Y (subject)
Line 4: Waiting on: status
Line 5: Total messages: N  Unread: build1=X build2=Y build3=Z build4=W
Line 6: (blank)
Line 7+: Full last message body (complete text, all lines)
```

**Example**:
```
Build1 messages: 21  Last message: 2025-10-31 14:03
Build2 messages: 18  Last message: 2025-10-31 12:46
Last message from: build1 to build2 (VNFCodex vs VNFCopilot update)
Waiting on: Build1 (15 unread)
Total messages: 41  Unread: build1=15 build2=0 build3=1 build4=1

Latest message body:
VNFCodex adds full VNF dictionary lifecycle (schema tables, VO/DAO, manager)...
(full message text continues)
```

## New Scripts

### 1. check_unread_messages.sh

**Purpose**: Check for unread messages and display status for one or all servers.

**Usage**:
```bash
# Check unread for specific server
./check_unread_messages.sh build2

# Check unread for all servers
./check_unread_messages.sh all
```

**Features**:
- Displays unread count per server
- Shows first unread message details
- Creates/updates `coordination/unread_messages_status.json`
- Returns exit code 1 if current server has unread messages
- Provides clear visual indicators ([OK] no unread, [!] has unread)

**Output Example**:
```
======================================
UNREAD MESSAGES STATUS - build2
======================================

[!]  YOU HAVE 5 UNREAD MESSAGE(S)

[INFO] From: build1 | Time: 2025-10-31T14:03:30Z
Subject: VNFCodex vs VNFCopilot update
ID: msg_1761919410_4255

VNFCodex adds full VNF dictionary lifecycle...
──────────────────────────────────────────────────────────
```

### 2. read_conversation_thread.sh

**Purpose**: Read and display the entire conversation thread with filtering options.

**Usage**:
```bash
# Read all messages for specific server
./read_conversation_thread.sh build2

# Read all messages across all servers
./read_conversation_thread.sh all

# Show only last 10 messages
./read_conversation_thread.sh build2 --limit 10

# Show only unread messages
./read_conversation_thread.sh build2 --unread-only

# Output as JSON
./read_conversation_thread.sh build2 --format json
```

**Features**:
- Beautiful formatted output with box drawing characters
- Filters by server (sender or recipient)
- Filters by read/unread status
- Limits to last N messages
- JSON or text output format
- Message summary by sender and type
- Unread status for all servers

**Output Example**:
```
════════════════════════════════════════════════════════════════════════
           COMPLETE CONVERSATION THREAD
════════════════════════════════════════════════════════════════════════
Filter: Messages for/from build2
Total Messages: 41
Generated: 2025-10-31T14:00:00Z
════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│ Message ID: msg_1761919410_4255
│ From: build1 → To: build2
│ Type: INFO | Priority: normal
│ Timestamp: 2025-10-31T14:03:30Z
│ Status: [!]  UNREAD
├─────────────────────────────────────────────────────────────────────────┤
│ Subject: VNFCodex vs VNFCopilot update
├─────────────────────────────────────────────────────────────────────────┤
│ VNFCodex adds full VNF dictionary lifecycle...
└─────────────────────────────────────────────────────────────────────────┘

MESSAGE SUMMARY:
────────────────
  build1: 21 messages sent
  build2: 18 messages sent

BY TYPE:
  info: 38 messages
  warning: 2 messages
  request: 1 messages

UNREAD STATUS:
  build1: [!]  15 unread messages
  build2: [OK] No unread messages
  build3: [!]  1 unread messages
  build4: [!]  1 unread messages
```

### 3. update_message_status_txt.sh

**Purpose**: Update `message_status.txt` with current messaging status.

**Usage**:
```bash
./update_message_status_txt.sh
```

**Features**:
- Calculates total message counts
- Counts unread messages per server
- Formats timestamps as YYYY-MM-DD HH:MM
- Includes full last message body
- Determines "Waiting on" status based on unread counts
- Auto-commits and pushes to GitHub

**Called By**:
- Manual execution
- Can be integrated into heartbeat or message processing workflows

## Updated Setup Scripts

All setup scripts (`setup_build1.sh`, `setup_build2.sh`, `setup_build3.sh`, `setup_build4.sh`) now include:

### New Steps (Steps 4-5):

**Step 4: Read Conversation Thread**
```
════════════════════════════════════════════════════════════════
 IMPORTANT: Build servers must read the entire conversation
 history to understand context and previous communications.
════════════════════════════════════════════════════════════════
```

- Automatically reads last 10 messages on setup
- Provides command to read full history
- Ensures servers understand conversation context

**Step 5: Check for Unread Messages**
```
════════════════════════════════════════════════════════════════
 [!]  YOU HAVE UNREAD MESSAGES!
 Please review and respond to unread messages before proceeding.
════════════════════════════════════════════════════════════════
```

- Checks unread status automatically
- Displays warning if unread messages exist
- Provides commands to view and mark messages as read

### Enhanced Command Reference

Setup scripts now display comprehensive command reference:

```
IMPORTANT COMMANDS:
  Check unread messages:
    cd /root/Build/scripts && ./check_unread_messages.sh build2

  Read full conversation thread:
    cd /root/Build/scripts && ./read_conversation_thread.sh build2

  View only unread messages:
    cd /root/Build/scripts && ./read_conversation_thread.sh build2 --unread-only

  Mark messages as read:
    cd /root/Build/scripts && ./mark_messages_read.sh build2

  Send a message:
    cd /root/Build/scripts && ./send_message.sh build2 build1 info "Subject" "Message body"

  Update message status:
    cd /root/Build/scripts && ./update_message_status_txt.sh

  Check system health:
    cd /root/Build/scripts && ./check_health.sh
```

## Workflow Integration

### Server Initialization Workflow

1. **Clone/Update Repository** (setup script step 1-3)
2. **Read Conversation Thread** (NEW - step 4)
   - Displays last 10 messages
   - Provides context for new servers
3. **Check Unread Messages** (NEW - step 5)
   - Alerts if unread messages exist
   - Displays unread message details
   - Prompts to review before proceeding
4. **Start Heartbeat Daemon** (step 6-7)

### Ongoing Operations Workflow

1. **Receive New Message**
   - Message arrives in `coordination/messages.json`
   - `unread_messages_status.json` automatically updated
2. **Check Unread Status**
   - Run `./check_unread_messages.sh <server_id>`
   - Identify unread messages
3. **Read Messages**
   - Run `./read_conversation_thread.sh <server_id> --unread-only`
   - Review full conversation context if needed
4. **Respond to Messages**
   - Run `./send_message.sh` to reply
5. **Mark as Read**
   - Run `./mark_messages_read.sh <server_id>`
6. **Update Status**
   - Run `./update_message_status_txt.sh`
   - Commit and push changes

## Benefits

### 1. Context Awareness
- Servers now read entire conversation history on startup
- New servers understand previous communications
- Prevents duplication and miscommunication

### 2. Unread Tracking
- Clear visibility of pending messages
- Per-server unread counters
- Automated status updates

### 3. Enhanced message_status.txt
- Full last message body visible on GitHub
- Total and per-server message counts
- Unread counts prominently displayed (line 5)
- "Waiting on" status based on unread messages

### 4. Better Coordination
- Servers know when they have pending messages
- Clear workflow for checking and responding
- Automatic status tracking

### 5. Audit Trail
- Complete conversation history always accessible
- Unread status tracked in version control
- Message statistics maintained

## File Dependencies

```
New Files:
├── scripts/check_unread_messages.sh          (NEW)
├── scripts/read_conversation_thread.sh       (NEW)
├── scripts/update_message_status_txt.sh      (NEW)
└── coordination/unread_messages_status.json  (AUTO-GENERATED)

Updated Files:
├── scripts/setup_build1.sh                   (UPDATED)
├── scripts/setup_build2.sh                   (UPDATED)
├── scripts/setup_build3.sh                   (UPDATED)
├── scripts/setup_build4.sh                   (UPDATED)
└── message_status.txt                        (FORMAT CHANGED)

Existing Files (unchanged):
├── coordination/messages.json
├── coordination/message_stats.json
├── scripts/send_message.sh
├── scripts/mark_messages_read.sh
└── scripts/read_messages.sh
```

## Migration Notes

### For Existing Servers

1. **Pull Latest Changes**:
   ```bash
   cd /root/Build
   git pull origin main
   chmod +x scripts/*.sh
   ```

2. **Read Conversation History**:
   ```bash
   cd /root/Build/scripts
   ./read_conversation_thread.sh <server_id>
   ```

3. **Check Unread Messages**:
   ```bash
   ./check_unread_messages.sh <server_id>
   ```

4. **Update Message Status**:
   ```bash
   ./update_message_status_txt.sh
   ```

### For New Servers

Just run the setup script - it will automatically:
- Read conversation history
- Check for unread messages
- Display all necessary commands

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git
cd Build/scripts && ./setup_build<N>.sh
```

## Testing

To test the new functionality:

```bash
# Test unread message checking
cd /root/Build/scripts
./check_unread_messages.sh all

# Test conversation thread reading
./read_conversation_thread.sh build2
./read_conversation_thread.sh build2 --limit 5
./read_conversation_thread.sh build2 --unread-only

# Test message status update
./update_message_status_txt.sh
cat /root/Build/message_status.txt

# Verify unread status file
cat /root/Build/coordination/unread_messages_status.json | jq '.'
```

## Future Enhancements

Potential improvements for future versions:

1. **Email/Notification Integration**
   - Send email alerts when unread messages arrive
   - Integrate with monitoring systems

2. **Message Priority Escalation**
   - Auto-escalate high-priority unread messages
   - Timeout warnings for old unread messages

3. **Conversation Threading**
   - Link related messages together
   - Display conversation threads

4. **Search Functionality**
   - Search messages by keyword
   - Filter by date range, sender, type

5. **Web Dashboard**
   - Real-time message view
   - Interactive message management

## Support

For questions or issues with the unread message tracking system:

1. Check this documentation
2. Review script help: `./check_unread_messages.sh --help`
3. Check logs: `/var/log/heartbeat-build*.log`
4. Review message history: `./read_conversation_thread.sh all`

## Changelog

### Version 2.0 (2025-10-31)
- [OK] Added `check_unread_messages.sh` script
- [OK] Added `read_conversation_thread.sh` script
- [OK] Added `update_message_status_txt.sh` script
- [OK] Created `coordination/unread_messages_status.json`
- [OK] Enhanced `message_status.txt` format (line 5 + full message body)
- [OK] Updated all setup scripts to check unread and read thread
- [OK] Integrated unread checking into server initialization

### Version 1.0 (2025-10-29)
- Initial message coordination system
- Basic send/read/mark message scripts

---

**End of Enhancement Summary**
