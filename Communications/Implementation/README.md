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

Alternatively, use the bundled helper script from the main repository to wire the Code02 reliability defaults:

```bash
cd /path/to/Build
scripts/run_code02_message_monitor.sh code2 10
```

The helper exposes the same options while ensuring the watcher writes heartbeats and metrics where the watchdog tooling expects them.

### Send a Message

```bash
# Basic usage
python send_message.py "Hello fleet" "Test Subject" --to all

# Windows
python send_message.py "Status update" --to code2

# Linux
python3 send_message.py "Task complete" "Task Report" --to architect
```

## Quick Start

```bash
# Clone repository
git clone https://github.com/alexandremattioli/Build.git
cd Build/Communications/Implementation

# Install dependencies
pip install -r requirements.txt

# Start monitor
python message_monitor.py --repo /path/to/Build --server code2
```

## Code01 reliability features

- **Persistent state & cleanup**: stale `.git/index.lock` files are removed and processed IDs are stored in `.watch_messages_state_<server>.json` so restarts pick up where they left off.
- **Circuit breaker**: repeated git/network failures keep the loop paused until the remote recovers.
- **Structured JSON logging**: `StructuredLogger` writes to `logs/watch_messages.log` (configurable) while keeping console output colored and informative.
- **Heartbeat signals**: `/var/run/watch_messages.heartbeat` and `/var/run/autoresponder_<server>.heartbeat` are touched every loop so external watchdogs can detect liveness.
- **Metrics**: `logs/watch_metrics.json` and `logs/autoresponder_metrics.json` record operation timings, success counts, and errors for auditing and dashboards.
- **Retry queue**: failed auto-responses are serialized via `MessageQueue` and flushed automatically once git/network operations succeed again.

## GitHub Repository

https://github.com/alexandremattioli/Build/tree/main/Communications/Implementation
