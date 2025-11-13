"""
Message Queue System
Queues failed messages for automatic retry
"""

import json
import os
import time
from typing import List, Dict, Any, Optional
from pathlib import Path


class MessageQueue:
    """Queue for failed messages with retry logic"""
    
    def __init__(self, build_repo_path: str, max_attempts: int = 5):
        self.build_repo_path = Path(build_repo_path)
        self.queue_path = self.build_repo_path / "code2" / "queue" / "message_queue.json"
        self.max_attempts = max_attempts
        self._ensure_queue_exists()
    
    def _ensure_queue_exists(self):
        """Ensure queue file and directory exist"""
        self.queue_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.queue_path.exists():
            self._save_queue({"messages": []})
    
    def _load_queue(self) -> Dict[str, List[Dict[str, Any]]]:
        """Load queue from disk"""
        try:
            with open(self.queue_path, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            return {"messages": []}
    
    def _save_queue(self, queue: Dict[str, List[Dict[str, Any]]]):
        """Save queue to disk"""
        with open(self.queue_path, 'w') as f:
            json.dump(queue, f, indent=2)
    
    def enqueue(self, message: Dict[str, Any]):
        """Add message to queue"""
        queue = self._load_queue()
        message['queued_at'] = time.time()
        message['attempts'] = 0
        message['id'] = f"queued_{int(time.time())}_{len(queue['messages'])}"
        queue['messages'].append(message)
        self._save_queue(queue)
    
    def get_pending(self) -> List[Dict[str, Any]]:
        """Get messages with attempts < max_attempts"""
        queue = self._load_queue()
        return [msg for msg in queue['messages'] if msg.get('attempts', 0) < self.max_attempts]
    
    def mark_sent(self, message_id: str):
        """Remove message from queue after successful send"""
        queue = self._load_queue()
        queue['messages'] = [msg for msg in queue['messages'] if msg.get('id') != message_id]
        self._save_queue(queue)
    
    def increment_attempts(self, message_id: str):
        """Increment retry attempts for a message"""
        queue = self._load_queue()
        for msg in queue['messages']:
            if msg.get('id') == message_id:
                msg['attempts'] = msg.get('attempts', 0) + 1
                msg['last_attempt'] = time.time()
                break
        self._save_queue(queue)
