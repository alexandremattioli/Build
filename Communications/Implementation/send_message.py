#!/usr/bin/env python3
"""
Send Message (sm) - Send coordination messages
Cross-platform message sending with verification and locking
"""

import json
from update_message_status import update_message_status
from pathlib import Path
import sys
import time
import subprocess
import random
from pathlib import Path
from datetime import datetime
from typing import Optional


class GitLock:
    """File-based lock for coordinating git operations"""
    
    def __init__(self, repo_path: Path, timeout: int = 30):
        self.lock_file = repo_path / ".git_lock"
        self.timeout = timeout
        self.acquired = False
        
    def acquire(self):
        """Acquire lock with timeout and random backoff"""
        start_time = time.time()
        
        while time.time() - start_time < self.timeout:
            try:
                # Try to create lock file exclusively
                self.lock_file.touch(exist_ok=False)
                self.acquired = True
                return True
            except FileExistsError:
                # Lock exists, check if stale
                if self.lock_file.exists():
                    lock_age = time.time() - self.lock_file.stat().st_mtime
                    if lock_age > 60:  # Stale lock (>1 minute)
                        self.lock_file.unlink()
                        continue
                
                # Wait with exponential backoff + jitter
                wait = min(5, 0.1 * (2 ** (time.time() - start_time))) + random.uniform(0, 0.5)
                time.sleep(wait)
        
        return False
    
    def release(self):
        """Release the lock"""
        if self.acquired and self.lock_file.exists():
            try:
                self.lock_file.unlink()
            except:
                pass
            self.acquired = False
    
    def __enter__(self):
        if not self.acquire():
            raise TimeoutError("Could not acquire git lock")
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()


def send_message(body: str, subject: Optional[str] = None, to: str = "all",
                 priority: str = "normal", msg_type: str = "info",
                 from_sender: str = "architect",
                 build_repo_path: str = "K:/Projects/Build") -> bool:
    """Send a coordination message with verification and locking"""

    repo_path = Path(build_repo_path)
    messages_file = repo_path / "coordination" / "messages.json"

    if not messages_file.exists():
        print(f"Error: Messages file not found: {messages_file}")
        return False

    # Default subject
    if not subject:
        subject = f"Message from {from_sender}"

    try:
        # Acquire lock before git operations
        with GitLock(repo_path) as lock:
            
            # Pull first
            print(f"Pulling latest messages...")
            subprocess.run(["git", "pull", "origin", "main"],
                          cwd=repo_path, capture_output=True, check=False)
            
            # Load messages
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

            # Git operations (still under lock)
            try:
                subprocess.run(["git", "add", "coordination/messages.json"],
                              cwd=repo_path, check=True)

                subprocess.run(["git", "commit", "-m",
                               f"{from_sender} -> {to}: {subject}"],
                              cwd=repo_path, check=True)

                # Push with retry
                max_retries = 3
                for attempt in range(max_retries):
                    result = subprocess.run(["git", "push", "origin", "main"],
                                          cwd=repo_path, capture_output=True)
                    if result.returncode == 0:
                        break
                    
                    if attempt < max_retries - 1:
                        # Pull and retry
                        subprocess.run(["git", "pull", "--rebase", "origin", "main"],
                                      cwd=repo_path, capture_output=True, check=False)
                        time.sleep(random.uniform(0.5, 1.5))
                else:
                    raise subprocess.CalledProcessError(result.returncode, "git push")

                # Verify by pulling and checking
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
                    
                    # Auto-update message_status.txt
                    try:
                        update_message_status(Path(build_repo_path))
                        print("  Status file updated")
                    except Exception as e:
                        print(f"  Note: Status file not updated: {e}")
                    return True
                else:
                    print(f"✗ Verification failed: Message not found in remote")
                    return False

            except subprocess.CalledProcessError as e:
                print(f"Git operation failed: {e}")
                return False

    except TimeoutError as e:
        print(f"✗ Could not acquire lock: {e}")
        print("  Another process is currently committing. Try again in a moment.")
        return False
    except Exception as e:
        print(f"Error during send: {e}")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python send_message.py <body> [subject] [--to <recipient>] [--from <sender>] [--priority <level>] [--type <type>]")
        print("Example: python send_message.py 'Hello fleet' 'Test message' --to all --from code2")
        sys.exit(1)

    body = sys.argv[1]
    subject = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else None

    # Parse additional arguments
    to = "all"
    from_sender = "architect"
    priority = "normal"
    msg_type = "info"
    
    for i, arg in enumerate(sys.argv):
        if arg == "--to" and i + 1 < len(sys.argv):
            to = sys.argv[i + 1]
        elif arg == "--from" and i + 1 < len(sys.argv):
            from_sender = sys.argv[i + 1]
        elif arg == "--priority" and i + 1 < len(sys.argv):
            priority = sys.argv[i + 1]
        elif arg == "--type" and i + 1 < len(sys.argv):
            msg_type = sys.argv[i + 1]

    success = send_message(body, subject, to, priority, msg_type, from_sender)
    sys.exit(0 if success else 1)
