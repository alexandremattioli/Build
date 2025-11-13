# Cross-Platform Message Monitoring System

Python-based message monitoring system for Windows and Linux servers.

## Features

- **Cross-platform**: Works on Windows, Linux, and macOS
- **Circuit breaker**: Prevents cascading failures
- **Message queue**: Automatic retry of failed messages
- **Health monitoring**: System resources and git repository
- **Structured logging**: JSON logs with severity levels
- **Network checks**: Pre-flight connectivity validation
- **Metrics collection**: Performance tracking and analysis
- **Auto-response**: Intelligent automatic replies

## Installation

### Prerequisites

- Python 3.8 or higher
- Git installed and configured
- Network access to GitHub

### Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Or with Python 3 explicitly
python3 -m pip install -r requirements.txt
```

## Usage

### Start the Monitor

```bash
# Windows
python message_monitor.py --repo K:/Projects/Build --server code2 --interval 10

# Linux
python3 message_monitor.py --repo /path/to/Build --server code2 --interval 10
```

### Send a Message

```bash
# Basic usage
python send_message.py "Hello fleet" "Test Subject" --to all

# Windows
python send_message.py "Status update" --to code2

# Linux
python3 send_message.py "Task complete" "Task Report" --to architect
```

### Check System Health

```python
from system_health import get_system_health

health = get_system_health("/path/to/Build")
print(health)
```

### View Metrics

```python
from monitoring_metrics import MetricsCollector

metrics = MetricsCollector("/path/to/Build")
summary = metrics.get_summary(hours=24)
print(summary)
```

## Architecture

### Core Components

1. **message_monitor.py**: Main monitoring loop with auto-response
2. **send_message.py**: Send messages with verification
3. **circuit_breaker.py**: Circuit breaker pattern implementation
4. **message_queue.py**: Failed message queue with retry
5. **structured_log.py**: JSON structured logging
6. **network_check.py**: Network connectivity testing
7. **system_health.py**: System resource monitoring
8. **monitoring_metrics.py**: Performance metrics collection

### Reliability Features

- **Exponential backoff**: 2s, 4s, 8s retry delays
- **Circuit breaker**: 5 failure threshold, 5-minute timeout
- **Message queue**: Max 5 retry attempts per message
- **Health checks**: Every 100 seconds (10 iterations)
- **Git lock detection**: Auto-remove stale locks >2 minutes

## Running as a Service

### Linux (systemd)

Create `/etc/systemd/system/message-monitor.service`:

```ini
[Unit]
Description=Message Monitor Service
After=network.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/path/to/Build/python
ExecStart=/usr/bin/python3 message_monitor.py --repo /path/to/Build --server code2
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable message-monitor
sudo systemctl start message-monitor
sudo systemctl status message-monitor
```

### Windows (Task Scheduler)

Create a scheduled task:

```powershell
$action = New-ScheduledTaskAction -Execute "python" -Argument "K:\Projects\Build\python\message_monitor.py --repo K:/Projects/Build --server code2"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName "MessageMonitor" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

## Configuration

### Environment Variables

```bash
# Set repository path
export BUILD_REPO_PATH="/path/to/Build"

# Set server ID
export SERVER_ID="code2"

# Set polling interval
export MONITOR_INTERVAL=10
```

### Command Line Arguments

```
--repo PATH       Build repository path (default: K:/Projects/Build)
--server ID       Server identifier (default: code2)
--interval SEC    Polling interval in seconds (default: 10)
```

## Monitoring and Logs

### Log Files

- `code2/logs/structured.log`: JSON structured logs
- `code2/logs/metrics.json`: Performance metrics
- `code2/queue/message_queue.json`: Failed message queue

### View Logs

```bash
# Tail structured log
tail -f code2/logs/structured.log | python -m json.tool

# View metrics
python -c "import json; print(json.dumps(json.load(open('code2/logs/metrics.json')), indent=2))"
```

## Troubleshooting

### Monitor Not Starting

1. Check Python version: `python --version` (need 3.8+)
2. Install dependencies: `pip install -r requirements.txt`
3. Verify git access: `git pull` in repo directory
4. Check permissions on log directories

### Messages Not Sending

1. Verify git credentials configured
2. Check network connectivity: `python -c "from network_check import test_connectivity; print(test_connectivity())"`
3. Review structured logs for errors
4. Check message queue: `cat code2/queue/message_queue.json`

### High Resource Usage

1. Check health: `python -c "from system_health import get_system_health; print(get_system_health('.'))`
2. Review metrics: Check `code2/logs/metrics.json`
3. Verify no duplicate processes running
4. Check git repository size and history

## Migration from PowerShell

The Python version provides equivalent functionality to the PowerShell scripts:

| PowerShell | Python |
|------------|--------|
| `sm.ps1` | `send_message.py` |
| `Start-MessageMonitor.ps1` | `message_monitor.py` |
| `CircuitBreaker.ps1` | `circuit_breaker.py` |
| `MessageQueue.ps1` | `message_queue.py` |
| `Write-StructuredLog.ps1` | `structured_log.py` |
| `Test-NetworkConnectivity.ps1` | `network_check.py` |
| `Get-SystemHealth.ps1` | `system_health.py` |
| `Get-MonitoringMetrics.ps1` | `monitoring_metrics.py` |

### Key Differences

- Uses Python's native cross-platform path handling
- JSON parsing via built-in `json` module
- Subprocess module for git operations
- ANSI colors work on Windows 10+ and Linux

## Contributing

When adding features:

1. Maintain cross-platform compatibility
2. Use `pathlib.Path` for file paths
3. Test on both Windows and Linux
4. Update documentation
5. Add metrics for new operations

## License

Part of the Build coordination system.
