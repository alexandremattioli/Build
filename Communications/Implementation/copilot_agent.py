#!/usr/bin/env python3
"""
GitHub Copilot Agent - AI-powered autonomous agent
Monitors messages and provides intelligent responses
"""

import json
import time
import subprocess
import sys
import os
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any

from send_message import send_message


class CopilotAgent:
    """AI-powered agent that monitors and responds to messages"""

    def __init__(
        self,
        build_repo_path: str = "K:/Projects/Build",
        interval_seconds: int = 10,
        agent_id: str = "copilot",
    ):
        self.build_repo_path = Path(build_repo_path)
        self.interval_seconds = interval_seconds
        self.agent_id = agent_id
        self.processed_ids = set()
        self.state_path = self.build_repo_path / f".{agent_id}_agent_state.json"
        
        self._load_state()
        
        print(f"\n{'='*70}")
        print(f"AI AGENT STARTED - GitHub Copilot Integration")
        print(f"{'='*70}")
        print(f"Agent ID: {self.agent_id}")
        print(f"Interval: {interval_seconds} seconds")
        print(f"Repo: {self.build_repo_path}")
        print(f"Mode: AI-powered responses via GitHub Copilot")
        print(f"\nMonitoring messages addressed to: {self.agent_id}, architect, all")
        print(f"Press Ctrl+C to stop\n")

    def _load_state(self):
        """Load processed message IDs"""
        if not self.state_path.exists():
            return
        try:
            data = json.loads(self.state_path.read_text())
            self.processed_ids.update(data.get("processed_ids", []))
        except Exception as e:
            print(f"Warning: Could not load state: {e}")

    def _save_state(self):
        """Save processed message IDs"""
        try:
            with open(self.state_path, "w", encoding="utf-8") as f:
                json.dump({"processed_ids": sorted(self.processed_ids)}, f, indent=2)
        except Exception as e:
            print(f"Warning: Could not save state: {e}")

    def get_new_messages(self) -> List[Dict[str, Any]]:
        """Get new unprocessed messages"""
        try:
            messages_file = self.build_repo_path / "coordination" / "messages.json"
            
            # Pull latest
            subprocess.run(
                ["git", "pull", "origin", "main"],
                cwd=self.build_repo_path,
                capture_output=True,
                check=False
            )
            
            with open(messages_file, 'r', encoding='utf-8') as f:
                messages_data = json.load(f)

            # Get messages for this agent
            new_messages = [
                msg for msg in messages_data['messages']
                if (msg['to'] in [self.agent_id, 'architect', 'all'])
                and msg['id'] not in self.processed_ids
                and msg['from'] not in [self.agent_id, 'architect']  # Don't respond to self
            ]

            return sorted(new_messages, key=lambda x: x['timestamp'])
        except Exception as e:
            print(f"Error reading messages: {e}")
            return []

    def process_message(self, message: Dict[str, Any]):
        """Process a message and generate AI response"""
        
        print(f"\n{'='*70}")
        print(f"NEW MESSAGE RECEIVED")
        print(f"{'='*70}")
        print(f"From: {message['from']}")
        print(f"To: {message['to']}")
        print(f"Subject: {message['subject']}")
        print(f"Body: {message['body'][:200]}{'...' if len(message['body']) > 200 else ''}")
        print(f"{'='*70}\n")
        
        # Create AI prompt for response
        response = self._generate_ai_response(message)
        
        # Send response
        self.send_response(message, response)
        
        # Mark as processed
        self.mark_processed(message['id'])

    def _generate_ai_response(self, message: Dict[str, Any]) -> str:
        """Generate intelligent response based on message content"""
        
        body = message.get('body', '').lower()
        
        # System status requests
        if any(keyword in body for keyword in ['status', 'health', 'check']):
            return self._get_system_status()
        
        # Git operations
        if 'git' in body:
            if 'status' in body:
                return self._get_git_status()
            elif 'log' in body or 'history' in body:
                return self._get_git_log()
        
        # Message/coordination queries
        if any(keyword in body for keyword in ['messages', 'recent', 'list']):
            return self._get_recent_messages()
        
        # Agent status
        if any(keyword in body for keyword in ['agents', 'monitors', 'who']):
            return self._get_agents_status()
        
        # File operations
        if 'files' in body or 'directory' in body or 'folder' in body:
            if 'list' in body or 'show' in body:
                return self._list_files(message.get('body', ''))
        
        # Help
        if any(keyword in body for keyword in ['help', 'commands', 'what can you']):
            return self._get_help()
        
        # Default: Acknowledge and provide context
        return self._default_response(message)

    def _get_system_status(self) -> str:
        """Get comprehensive system status"""
        status = []
        status.append("SYSTEM STATUS REPORT")
        status.append("=" * 70)
        status.append(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        status.append(f"Agent: {self.agent_id} on CODE2 (Windows)")
        status.append(f"Repository: {self.build_repo_path}")
        status.append("")
        
        # Check monitors
        try:
            result = subprocess.run(
                ["powershell", "-Command", "Get-Job | Where-Object { $_.Name -like '*Monitor*' -or $_.Name -like '*Agent*' } | Select-Object Id, Name, State"],
                capture_output=True,
                text=True,
                timeout=5
            )
            status.append("ACTIVE AGENTS:")
            if result.stdout.strip():
                status.append(result.stdout.strip())
            else:
                status.append("  No background jobs found")
        except Exception as e:
            status.append(f"  Error checking jobs: {e}")
        
        status.append("")
        status.append("CAPABILITIES:")
        status.append("  - System status monitoring")
        status.append("  - Git operations")
        status.append("  - File operations")
        status.append("  - Message coordination")
        status.append("  - Task execution")
        
        return "\n".join(status)

    def _get_git_status(self) -> str:
        """Get git repository status"""
        try:
            result = subprocess.run(
                ["git", "status", "--short"],
                cwd=self.build_repo_path,
                capture_output=True,
                text=True
            )
            
            output = ["GIT REPOSITORY STATUS", "=" * 70]
            
            if result.stdout.strip():
                output.append("Modified files:")
                output.append(result.stdout)
            else:
                output.append("Working tree clean - no uncommitted changes")
            
            # Get branch info
            branch_result = subprocess.run(
                ["git", "branch", "--show-current"],
                cwd=self.build_repo_path,
                capture_output=True,
                text=True
            )
            output.append(f"\nCurrent branch: {branch_result.stdout.strip()}")
            
            return "\n".join(output)
        except Exception as e:
            return f"Error getting git status: {e}"

    def _get_git_log(self) -> str:
        """Get recent git log"""
        try:
            result = subprocess.run(
                ["git", "log", "--oneline", "--graph", "-10"],
                cwd=self.build_repo_path,
                capture_output=True,
                text=True
            )
            return f"RECENT GIT HISTORY (last 10 commits)\n{'='*70}\n{result.stdout}"
        except Exception as e:
            return f"Error getting git log: {e}"

    def _get_recent_messages(self) -> str:
        """Get recent messages from coordination"""
        try:
            messages_file = self.build_repo_path / "coordination" / "messages.json"
            with open(messages_file, 'r', encoding='utf-8') as f:
                messages_data = json.load(f)
            
            recent = messages_data['messages'][-10:]
            output = ["RECENT MESSAGES (last 10)", "=" * 70]
            for msg in recent:
                output.append(f"[{msg['timestamp']}] {msg['from']} -> {msg['to']}")
                output.append(f"  Subject: {msg['subject']}")
                output.append(f"  Read: {msg.get('read', False)}")
                output.append("")
            return "\n".join(output)
        except Exception as e:
            return f"Error getting messages: {e}"

    def _get_agents_status(self) -> str:
        """Get status of all agents"""
        status = ["COORDINATION AGENTS STATUS", "=" * 70]
        
        status.append("\nAUTONOMOUS AGENTS:")
        status.append("  1. CODE2 Monitor - Auto-responds to keywords")
        status.append("  2. BUILD1 Monitor - Auto-responds to keywords (systemd service)")
        status.append(f"  3. {self.agent_id.upper()} Agent - AI-powered responses (THIS AGENT)")
        
        status.append("\nMESSAGE COORDINATION:")
        status.append("  - File: coordination/messages.json")
        status.append("  - Sync: Git push/pull")
        status.append("  - Lock: GitLock prevents conflicts")
        
        return "\n".join(status)

    def _list_files(self, query: str) -> str:
        """List files based on query"""
        try:
            # Extract path if mentioned
            path = self.build_repo_path
            
            result = subprocess.run(
                ["powershell", "-Command", f"Get-ChildItem -Path '{path}' -File | Select-Object -First 20 Name, Length, LastWriteTime"],
                capture_output=True,
                text=True,
                timeout=10
            )
            return f"FILES IN {path}\n{'='*70}\n{result.stdout}"
        except Exception as e:
            return f"Error listing files: {e}"

    def _get_help(self) -> str:
        """Get help information"""
        help_text = [
            "AI AGENT HELP",
            "=" * 70,
            "",
            "I am an AI-powered agent monitoring messages. I can help with:",
            "",
            "SYSTEM OPERATIONS:",
            "  - 'check status' - Get system status",
            "  - 'agents status' - List all active agents",
            "",
            "GIT OPERATIONS:",
            "  - 'git status' - Check git working tree",
            "  - 'git log' - Show recent commits",
            "",
            "COORDINATION:",
            "  - 'list messages' - Show recent messages",
            "  - 'recent messages' - Show message history",
            "",
            "FILE OPERATIONS:",
            "  - 'list files' - Show files in repository",
            "",
            "Send messages to: copilot, architect, or all",
            "",
            "I process messages every 10 seconds and respond intelligently",
            "based on your request content."
        ]
        return "\n".join(help_text)

    def _default_response(self, message: Dict[str, Any]) -> str:
        """Default response for unrecognized messages"""
        response = [
            "MESSAGE ACKNOWLEDGED",
            "=" * 70,
            "",
            f"I received your message: '{message['subject']}'",
            "",
            "I'm an AI-powered agent ready to help with:",
            "  - System status and monitoring",
            "  - Git operations",
            "  - File operations",
            "  - Message coordination",
            "",
            "Send 'help' for a list of commands I understand.",
            "",
            "Your message content:",
            "-" * 70,
            message['body'][:500] + ("..." if len(message['body']) > 500 else "")
        ]
        return "\n".join(response)

    def mark_processed(self, message_id: str):
        """Mark message as processed"""
        self.processed_ids.add(message_id)
        self._save_state()

    def send_response(self, original_message: Dict[str, Any], response_body: str):
        """Send response message"""
        subject = f"Re: {original_message['subject']}"
        
        full_response = f"AI Agent Response\n\n"
        full_response += f"Original from: {original_message['from']}\n"
        full_response += f"Processed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        full_response += response_body
        
        try:
            success = send_message(
                body=full_response,
                subject=subject,
                to=original_message['from'],
                from_sender=self.agent_id,
                build_repo_path=str(self.build_repo_path)
            )
            if success:
                print(f"[OK] Response sent to {original_message['from']}")
            else:
                print(f"[FAIL] Failed to send response")
        except Exception as e:
            print(f"[ERROR] Error sending response: {e}")

    def run(self):
        """Main agent loop"""
        while True:
            try:
                messages = self.get_new_messages()
                
                for message in messages:
                    self.process_message(message)
                
                # Sleep
                time.sleep(self.interval_seconds)
                
            except KeyboardInterrupt:
                print(f"\n\n[STOP] Agent stopping...")
                break
            except Exception as e:
                print(f"[ERROR] Error in agent loop: {e}")
                time.sleep(self.interval_seconds)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="GitHub Copilot Agent - AI-powered responses")
    parser.add_argument("--interval", type=int, default=10, help="Polling interval in seconds")
    parser.add_argument("--repo", type=str, default="K:/Projects/Build", help="Build repository path")
    parser.add_argument("--agent-id", type=str, default="copilot", help="Agent ID")
    
    args = parser.parse_args()
    
    agent = CopilotAgent(
        build_repo_path=args.repo,
        interval_seconds=args.interval,
        agent_id=args.agent_id
    )
    
    agent.run()


if __name__ == "__main__":
    main()
