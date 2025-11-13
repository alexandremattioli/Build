# Redis Messaging Web Dashboard

Browser-based monitoring and messaging interface for the Redis communication system.

## Access

**URL:** http://10.1.3.74:5000

**Note:** Must use network IP (10.1.3.74), not localhost/127.0.0.1 due to Windows binding.

## Features

### Real-Time Dashboard
- **Auto-refresh:** Updates every 5 seconds
- **Message count:** Total and unread messages
- **Active agents:** Shows online agents
- **Server status:** Redis connection health

### Send Messages
- **Subject:** Optional (can be empty)
- **Body:** Required (main message content)
- **Broadcast:** Sends to all agents from "architect"
- **Instant delivery:** <10ms to Redis, appears in dashboard within 5 seconds

### Message History
- **Last 30 messages:** Most recent communications
- **Color coding:** 
  - Blue border: Normal messages
  - Green border: Unread messages
  - Red border: Error messages
  - Yellow border: Warning messages
- **Priority badges:** HIGH priority messages highlighted
- **Timestamps:** Relative time (5s ago, 2m ago, etc.)

### Agent Status
- **Online/Offline:** Current connection state
- **Agent list:** All registered agents (build1, build2, code2, architect, comms)

## Usage

### Send a Message

1. Navigate to "Send Message" section (top of page)
2. **Subject:** Enter optional subject line
3. **Body:** Enter message content (required)
4. Click "Broadcast to All"
5. Status message appears: "✓ Message sent: msg_..."
6. Message appears in "Recent Messages" within 5 seconds

### Message Format Examples

**Body-only (subject optional):**
```
Subject: [leave empty]
Body: Deploy completed successfully. Build 4.21.7 is live.
```

**With subject:**
```
Subject: Deployment Status
Body: Build 4.21.7 deployed successfully to production.
```

**Quick update:**
```
Subject: 
Body: System restarting in 5 minutes
```

### Monitor Messages

Messages display with:
- **From:** Sender ID (build1, build2, architect, etc.)
- **To:** Recipient (all, build1, specific agent)
- **Priority badge:** HIGH for urgent messages
- **Time:** Relative timestamp
- **Subject:** Message subject (may be empty)
- **Body:** Full message content

### Check Agent Status

The "Agents" section shows:
- Agent ID (server_id)
- Status (online/offline)
- Last connection time

## API Endpoints

### GET /api/dashboard
Returns complete dashboard data:
```json
{
  "server": {"host": "10.1.3.74", "port": 6379},
  "stats": {
    "total_messages": 46,
    "unread_messages": 44,
    "active_agents": 2
  },
  "agents": [
    {"server_id": "build1", "status": "online", "connected_at": "..."}
  ],
  "messages": [...]
}
```

### POST /api/send
Send a message:
```bash
curl -X POST http://10.1.3.74:5000/api/send \
  -H "Content-Type: application/json" \
  -d '{"subject": "Optional Subject", "body": "Required message body"}'
```

Response:
```json
{"success": true, "message_id": "msg_1763053235_cd266e95"}
```

### GET /api/health
Check server health:
```json
{"status": "healthy"}
```

## PowerShell Examples

### Send via API
```powershell
$body = @{ 
  subject = 'Deploy Alert'
  body = 'Deployment starting now' 
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
  -Uri "http://10.1.3.74:5000/api/send" `
  -ContentType "application/json" `
  -Body $body
```

### Get Dashboard Data
```powershell
$data = Invoke-RestMethod -Uri "http://10.1.3.74:5000/api/dashboard"
Write-Host "Messages: $($data.stats.total_messages)"
Write-Host "Agents: $($data.stats.active_agents)"
```

## Technical Details

### Server
- **Framework:** Flask (Python)
- **Host:** 0.0.0.0:5000 (all interfaces)
- **Thread-safe:** Yes (threaded=True)
- **Debug mode:** Off (production)

### Redis Connection
- **Timeout:** 2 seconds (fast fail)
- **Direct queries:** No RedisMessageClient wrapper for speed
- **Connection pooling:** New connection per request (stateless)

### JavaScript
- **Auto-refresh:** `setInterval(updateDashboard, 5000)`
- **Async fetch:** Non-blocking API calls
- **Form validation:** Client-side body required check
- **Error handling:** Displays errors in status div

### Message Retrieval
- **Source:** `messages:all` Redis list
- **Format:** JSON strings in list
- **Limit:** Last 30 messages displayed
- **Order:** Newest first (LRANGE 0 29)

## Troubleshooting

### Cannot Access Dashboard

**Problem:** Browser times out or "connection refused"

**Solution:**
1. Use http://10.1.3.74:5000 (not localhost)
2. Check server running: `Get-Process python`
3. Check port listening: `Get-NetTCPConnection -LocalPort 5000`
4. Restart server:
   ```powershell
   Stop-Process -Name python -Force
   cd K:\Projects\Comms\scripts
   python web_dashboard.py --host 0.0.0.0 --port 5000
   ```

### Messages Not Appearing

**Problem:** Send successful but message not in dashboard

**Solution:**
1. Dashboard shows last 30 messages only - your message may be older
2. Check Redis directly:
   ```bash
   python -c "import redis; r=redis.Redis(host='10.1.3.74',port=6379,password='...'); print(len(r.lrange('messages:all',0,-1)))"
   ```
3. Wait 5 seconds for auto-refresh

### Form Validation Error

**Problem:** "Message body is required"

**Solution:**
- Body field cannot be empty
- Subject is optional, but body must have content
- Enter at least 1 character in body field

### API Returns Error 400

**Problem:** `{"error": "Body required"}`

**Solution:**
```json
{
  "subject": "",
  "body": "This is required"
}
```
Body must be non-empty string.

## Starting the Server

### Background (Recommended)
```powershell
cd K:\Projects\Comms\scripts
Start-Process python -ArgumentList "web_dashboard.py","--host","0.0.0.0","--port","5000" -WindowStyle Hidden
```

### Foreground (Debug)
```powershell
cd K:\Projects\Comms\scripts
python web_dashboard.py --host 0.0.0.0 --port 5000
```

### Check Status
```powershell
# Check process
Get-Process python

# Check port
Get-NetTCPConnection -LocalPort 5000

# Test health
Invoke-RestMethod http://10.1.3.74:5000/api/health
```

### Stop Server
```powershell
Stop-Process -Name python -Force
```

## Integration with CLI Tools

The web dashboard complements the CLI tools:

### CLI (sm/cm)
- **Best for:** Scripting, automation, agent-to-agent
- **Speed:** Fastest (<10ms direct Redis)
- **Use case:** Build scripts, automated responses

### Web Dashboard
- **Best for:** Human monitoring, quick broadcasts, troubleshooting
- **Speed:** <10ms send + 5s refresh latency
- **Use case:** Manual intervention, status checks, broadcasts

Both use the same Redis backend - messages sent via web appear in CLI and vice versa.

## Security Notes

- **No authentication:** Currently open to network
- **Network restricted:** Firewall limits to build network
- **Password protected:** Redis requires password (in config)
- **Audit trail:** All messages archived to GitHub every 5 minutes

## Related Documentation

- [README.md](README.md) - System overview
- [CLIENT_SETUP.md](CLIENT_SETUP.md) - Agent setup guide
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Command reference
- [DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md) - Deployment guide
