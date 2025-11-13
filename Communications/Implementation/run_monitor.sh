#!/bin/bash
cd /root/Build/Communications/Implementation

# Install/activate venv
if [ ! -d '.venv' ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate

# Install requirements
pip install -q -r requirements.txt

# Create logs directory
mkdir -p /root/Build/logs

# Run monitor with output logging
while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting monitor..."
    python3 message_monitor.py --server build1 --repo /root/Build --interval 10 2>&1 | tee -a /root/Build/logs/watch_messages.out
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monitor exited, restarting in 5s..."
    sleep 5
done
