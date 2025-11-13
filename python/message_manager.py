#!/usr/bin/env python3
"""
Enhanced Message Management System
Provides Python API for message operations with priority levels, archiving, and search
"""

import json
import os
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Any
from enum import Enum

class Priority(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    NORMAL = "normal"
    LOW = "low"

class MessageType(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    REQUEST = "request"
    RESPONSE = "response"
    HEARTBEAT = "heartbeat"

class MessageManager:
    """Enhanced message management with priority queuing and archiving"""
    
    def __init__(self, repo_path: str = None):
        self.repo_path = repo_path or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.messages_file = os.path.join(self.repo_path, "coordination", "messages.json")
        self.archive_dir = os.path.join(self.repo_path, "coordination", "archive")
        os.makedirs(self.archive_dir, exist_ok=True)
    
    def load_messages(self) -> Dict[str, Any]:
        """Load messages from file"""
        if not os.path.exists(self.messages_file):
            return {"messages": [], "schema_version": "1.0", "metadata": {}}
        
        with open(self.messages_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def save_messages(self, data: Dict[str, Any]):
        """Save messages to file"""
        data["metadata"]["last_modified"] = datetime.utcnow().isoformat() + "Z"
        
        with open(self.messages_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    
    def send_message(
        self,
        from_server: str,
        to_server: str,
        subject: str,
        body: str,
        priority: Priority = Priority.NORMAL,
        msg_type: MessageType = MessageType.INFO,
        reply_to: str = None,
        expires_days: int = None,
        metadata: Dict = None
    ) -> str:
        """
        Send a message with enhanced options
        
        Args:
            from_server: Sender server ID
            to_server: Recipient server ID or 'all'
            subject: Message subject
            body: Message body
            priority: Message priority level
            msg_type: Message type
            reply_to: Message ID this is replying to
            expires_days: Days until message auto-archives
            metadata: Additional metadata dict
        
        Returns:
            Message ID
        """
        data = self.load_messages()
        
        timestamp = datetime.utcnow()
        msg_id = f"msg_{int(timestamp.timestamp())}_{hash(body) % 10000}"
        
        message = {
            "id": msg_id,
            "from": from_server,
            "to": to_server,
            "subject": subject,
            "body": body,
            "timestamp": timestamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "priority": priority.value,
            "type": msg_type.value,
            "read": False
        }
        
        if reply_to:
            message["reply_to"] = reply_to
        
        if expires_days:
            expires_at = timestamp + timedelta(days=expires_days)
            message["expires_at"] = expires_at.strftime("%Y-%m-%dT%H:%M:%SZ")
        
        if metadata:
            message["metadata"] = metadata
        
        data["messages"].append(message)
        data["metadata"]["total_messages"] = len(data["messages"])
        
        self.save_messages(data)
        return msg_id
    
    def mark_read(self, message_id: str, server_id: str):
        """Mark message as read"""
        data = self.load_messages()
        
        for msg in data["messages"]:
            if msg["id"] == message_id:
                msg["read"] = True
                msg["read_at"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                msg["read_by"] = server_id
                break
        
        self.save_messages(data)
    
    def get_unread(self, server_id: str) -> List[Dict]:
        """Get unread messages for a server"""
        data = self.load_messages()
        return [
            msg for msg in data["messages"]
            if not msg.get("read", False) and (msg["to"] == server_id or msg["to"] == "all")
        ]
    
    def get_by_priority(self, server_id: str, priority: Priority) -> List[Dict]:
        """Get messages by priority level"""
        unread = self.get_unread(server_id)
        return [msg for msg in unread if msg.get("priority") == priority.value]
    
    def search(self, query: str, server_id: str = None, msg_type: str = None) -> List[Dict]:
        """Search messages by text, optionally filtered by server/type"""
        data = self.load_messages()
        results = []
        
        for msg in data["messages"]:
            # Server filter
            if server_id and msg["to"] != server_id and msg["to"] != "all":
                continue
            
            # Type filter
            if msg_type and msg.get("type") != msg_type:
                continue
            
            # Text search
            if query.lower() in msg.get("subject", "").lower() or query.lower() in msg.get("body", "").lower():
                results.append(msg)
        
        return results
    
    def archive_old_messages(self, days_old: int = 30) -> int:
        """Archive messages older than specified days"""
        data = self.load_messages()
        cutoff = datetime.utcnow() - timedelta(days=days_old)
        
        to_archive = []
        remaining = []
        
        for msg in data["messages"]:
            msg_time = datetime.fromisoformat(msg["timestamp"].replace("Z", "+00:00"))
            
            # Check expiration
            if "expires_at" in msg:
                expires = datetime.fromisoformat(msg["expires_at"].replace("Z", "+00:00"))
                if datetime.utcnow() > expires:
                    to_archive.append(msg)
                    continue
            
            # Check age
            if msg_time < cutoff and msg.get("read", False):
                to_archive.append(msg)
            else:
                remaining.append(msg)
        
        if to_archive:
            # Save archive
            archive_file = os.path.join(
                self.archive_dir,
                f"messages_archive_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
            )
            
            with open(archive_file, 'w', encoding='utf-8') as f:
                json.dump({"messages": to_archive, "archived_at": datetime.utcnow().isoformat() + "Z"}, f, indent=2)
            
            # Update main file
            data["messages"] = remaining
            data["metadata"]["total_messages"] = len(remaining)
            self.save_messages(data)
        
        return len(to_archive)
    
    def get_conversation(self, message_id: str) -> List[Dict]:
        """Get full conversation thread for a message"""
        data = self.load_messages()
        thread = []
        
        # Find original message
        original = next((m for m in data["messages"] if m["id"] == message_id), None)
        if not original:
            return thread
        
        thread.append(original)
        
        # Find replies
        def find_replies(msg_id):
            replies = [m for m in data["messages"] if m.get("reply_to") == msg_id]
            for reply in replies:
                thread.append(reply)
                find_replies(reply["id"])
        
        find_replies(message_id)
        
        # Sort by timestamp
        thread.sort(key=lambda x: x["timestamp"])
        return thread


if __name__ == "__main__":
    # CLI interface
    import argparse
    
    parser = argparse.ArgumentParser(description="Build Message Manager")
    parser.add_argument("action", choices=["send", "unread", "search", "archive", "thread"])
    parser.add_argument("--from", dest="from_server", required=False)
    parser.add_argument("--to", default="all")
    parser.add_argument("--subject", "-s")
    parser.add_argument("--body", "-b")
    parser.add_argument("--priority", "-p", default="normal", choices=["critical", "high", "normal", "low"])
    parser.add_argument("--type", "-t", default="info", choices=["info", "warning", "error", "request", "response"])
    parser.add_argument("--reply-to")
    parser.add_argument("--server", help="Server ID for filtering")
    parser.add_argument("--query", "-q", help="Search query")
    parser.add_argument("--message-id", "-m", help="Message ID for thread view")
    parser.add_argument("--days", type=int, default=30, help="Days for archive operation")
    
    args = parser.parse_args()
    
    manager = MessageManager()
    
    if args.action == "send":
        if not args.from_server or not args.subject or not args.body:
            print("Error: --from, --subject, and --body are required for send")
            exit(1)
        
        msg_id = manager.send_message(
            args.from_server,
            args.to,
            args.subject,
            args.body,
            Priority(args.priority),
            MessageType(args.type),
            args.reply_to
        )
        print(f"Message sent: {msg_id}")
    
    elif args.action == "unread":
        if not args.server:
            print("Error: --server required for unread")
            exit(1)
        
        messages = manager.get_unread(args.server)
        print(f"\n{len(messages)} unread messages for {args.server}:\n")
        for msg in messages:
            print(f"[{msg['priority'].upper()}] {msg['from']} → {msg['to']}")
            print(f"Subject: {msg['subject']}")
            print(f"Time: {msg['timestamp']}")
            print(f"Preview: {msg['body'][:100]}...")
            print()
    
    elif args.action == "search":
        if not args.query:
            print("Error: --query required for search")
            exit(1)
        
        results = manager.search(args.query, args.server, args.type)
        print(f"\nFound {len(results)} messages matching '{args.query}':\n")
        for msg in results:
            print(f"{msg['id']}: {msg['subject']} ({msg['from']} → {msg['to']})")
    
    elif args.action == "archive":
        count = manager.archive_old_messages(args.days)
        print(f"Archived {count} messages older than {args.days} days")
    
    elif args.action == "thread":
        if not args.message_id:
            print("Error: --message-id required for thread")
            exit(1)
        
        thread = manager.get_conversation(args.message_id)
        print(f"\nConversation thread ({len(thread)} messages):\n")
        for i, msg in enumerate(thread, 1):
            indent = "  " * (i - 1)
            print(f"{indent}{i}. {msg['from']}: {msg['subject']}")
            print(f"{indent}   {msg['timestamp']}")
