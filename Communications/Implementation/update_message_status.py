#!/usr/bin/env python3
"""
Update message_status.txt with current message statistics
Should be called after sending messages or periodically by AI agent
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List


def update_message_status(build_repo_path: Path) -> bool:
    """
    Update message_status.txt with current statistics
    
    Args:
        build_repo_path: Path to Build repository
    
    Returns:
        True if successful, False otherwise
    """
    
    try:
        messages_file = build_repo_path / "coordination" / "messages.json"
        status_file = build_repo_path / "message_status.txt"
        
        # Load messages
        with open(messages_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
            messages = data.get('messages', [])
        
        # Count by server
        servers = ['build1', 'build2', 'build3', 'build4', 'code1', 'code2', 'jh01', 'architect']
        counts = {}
        last_times = {}
        
        for server in servers:
            server_msgs = [m for m in messages if m.get('from') == server]
            counts[server] = len(server_msgs)
            if server_msgs:
                last_times[server] = server_msgs[-1].get('timestamp', 'unknown')
            else:
                last_times[server] = 'never'
        
        # Get last message
        last_msg = messages[-1] if messages else None
        
        # Generate status
        status = f"""=== BUILD COORDINATION MESSAGE STATUS ===
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

MESSAGE COUNTS BY SERVER:
  build1 messages: {counts['build1']}  Last: {last_times['build1'][:16] if last_times['build1'] != 'never' else 'never'}
  build2 messages: {counts['build2']}  Last: {last_times['build2'][:16] if last_times['build2'] != 'never' else 'never'}
  build3 messages: {counts['build3']}  Last: {last_times['build3'][:16] if last_times['build3'] != 'never' else 'never'}
  build4 messages: {counts['build4']}  Last: {last_times['build4'][:16] if last_times['build4'] != 'never' else 'never'}
  code1 messages: {counts['code1']}  Last: {last_times['code1'][:16] if last_times['code1'] != 'never' else 'never'}
  code2 messages: {counts['code2']}  Last: {last_times['code2'][:16] if last_times['code2'] != 'never' else 'never'}
  jh01 messages: {counts['jh01']}  Last: {last_times['jh01'][:16] if last_times['jh01'] != 'never' else 'never'}
  architect messages: {counts['architect']}  Last: {last_times['architect'][:16] if last_times['architect'] != 'never' else 'never'}

TOTAL MESSAGES: {len(messages)}

LAST MESSAGE:
  From: {last_msg.get('from') if last_msg else 'N/A'}
  To: {last_msg.get('to') if last_msg else 'N/A'}
  Subject: {last_msg.get('subject', 'N/A')[:80] if last_msg else 'N/A'}
  Time: {last_msg.get('timestamp', 'N/A')[:19] if last_msg else 'N/A'}
  Priority: {last_msg.get('priority', 'normal') if last_msg else 'N/A'}

Body:
{last_msg.get('body', 'N/A')[:500] if last_msg else 'N/A'}{'...' if last_msg and len(last_msg.get('body', '')) > 500 else ''}

AI AGENT STATUS:
  - CODE2: Running (Anti-Loop Active, Archival Enabled)
  - BUILD1: Check systemctl status build1-ai-agent.service
  - BUILD2: Awaiting deployment verification
  
RECENT FEATURES:
  - Message Archival System (automatic at 800 messages)
  - Anti-Loop Protection (prevents infinite response loops)
  - GitLock conflict prevention
  - Auto-archival keeps 400 most recent messages

DOCUMENTATION:
  - SM/CM Command Usage Guide (sent to all servers)
  - AI Agent Deployment Verification (in progress)
  - Anti-Loop Implementation Discussion (sent)
"""
        
        # Write status file
        with open(status_file, 'w', encoding='utf-8') as f:
            f.write(status)
        
        print(f"[STATUS] Updated message_status.txt - {len(messages)} messages")
        return True
        
    except Exception as e:
        print(f"[ERROR] Failed to update message_status.txt: {e}")
        return False


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 2:
        repo_path = Path.cwd()
    else:
        repo_path = Path(sys.argv[1])
    
    success = update_message_status(repo_path)
    sys.exit(0 if success else 1)
