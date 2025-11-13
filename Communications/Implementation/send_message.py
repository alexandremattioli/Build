#!/usr/bin/env python3
"""
Send Message (sm) - Send coordination messages
Cross-platform message sending with verification
"""

import json
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional


def send_message(body: str, subject: Optional[str] = None, to: str = "all",
                 priority: str = "normal", msg_type: str = "info",
                 from_sender: str = "architect",
                 build_repo_path: str = "K:/Projects/Build") -> bool:
    """Send a coordination message with verification"""

    repo_path = Path(build_repo_path)
    messages_file = repo_path / "coordination" / "messages.json"

    if not messages_file.exists():
        print(f"Error: Messages file not found: {messages_file}")
        return False

    # Default subject
    if not subject:
        subject = f"Message from {from_sender}"    # Load messages
    try:
        with open(messages_file, 'r', encoding='utf-8') as f:
            messages = json.load(f)
    except Exception as e:
        print(f"Error loading messages: {e}")
        return False
    
    # Create new message
    timestamp = int(time.time())
    message_id = f"msg_{timestamp}_{len(messages['messages'])}"
    
    new_message = {
        "id": message_id,
        "from": from_sender,
        "to": to,
        "subject": subject,
        "body": body,
        "type": msg_type,
        "priority": priority,
        "timestamp": datetime.utcnow().isoformat() + 'Z',
        "read": False,
        "ack_required": False
    }
    
    messages['messages'].append(new_message)
    
    # Save messages
    try:
        with open(messages_file, 'w', encoding='utf-8') as f:
            json.dump(messages, f, indent=2)
    except Exception as e:
        print(f"Error saving messages: {e}")
        return False
    
    print(f"Pulling latest messages...")
    
    # Git operations
    try:
        subprocess.run(["git", "pull", "origin", "main"], 
                      cwd=repo_path, capture_output=True, check=False)
        
        subprocess.run(["git", "add", "coordination/messages.json"], 
                      cwd=repo_path, check=True)
        
        subprocess.run(["git", "commit", "-m",
                       f"{from_sender} -> {to}: {subject}"],
                      cwd=repo_path, check=True)
        
        subprocess.run(["git", "push", "origin", "main"],
                      cwd=repo_path, check=True)        # Verify by pulling and checking
        subprocess.run(["git", "pull", "origin", "main"], 
                      cwd=repo_path, check=True)
        
        # Verify message exists
        with open(messages_file, 'r', encoding='utf-8') as f:
            verified_messages = json.load(f)
        
        message_exists = any(msg['id'] == message_id for msg in verified_messages['messages'])
        
        if message_exists:
            print(f"✓ Message sent and verified")
            print(f"  From: {from_sender}")
            print(f"  To: {to}")
            print(f"  Subject: {subject}")
            print(f"  Type: {msg_type} | Priority: {priority}")
            print(f"\nSUCCESS: Message ID {message_id}")
            return True
        else:
            print(f"✗ Verification failed: Message not found in remote")
            return False
            
    except subprocess.CalledProcessError as e:
        print(f"Git operation failed: {e}")
        return False
    except Exception as e:
        print(f"Error during send: {e}")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python send_message.py <body> [subject] [--to <recipient>]")
        print("Example: python send_message.py 'Hello fleet' 'Test message' --to all")
        sys.exit(1)
    
    body = sys.argv[1]
    subject = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else None
    
    # Parse additional arguments
    to = "all"
    for i, arg in enumerate(sys.argv):
        if arg == "--to" and i + 1 < len(sys.argv):
            to = sys.argv[i + 1]
    
    success = send_message(body, subject, to)
    sys.exit(0 if success else 1)
