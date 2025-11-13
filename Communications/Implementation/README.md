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

## GitHub Repository

https://github.com/alexandremattioli/Build/tree/main/Communications/Implementation
