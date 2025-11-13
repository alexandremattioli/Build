#!/usr/bin/env python3
"""
Architect Agent - Autonomous CLI agent for CODE2
Monitors messages and executes tasks autonomously
"""

import json
import time
import subprocess
import sys
import re
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any

from send_message import send_message


class ArchitectAgent:
    """Autonomous agent for executing tasks from messages"""

    def __init__(
        self,
        build_repo_path: str = "K:/Projects/Build",
        interval_seconds: int = 15,
        agent_id: str = "architect",
    ):
        self.build_repo_path = Path(build_repo_path)
        self.interval_seconds = interval_seconds
        self.agent_id = agent_id
        self.processed_ids = set()
        self.state_path = self.build_repo_path / f".architect_agent_state.json"
        
        self._load_state()
        
        print(f"\n{'='*60}")
        print(f"🤖 ARCHITECT AGENT STARTED")
        print(f"{'='*60}")
        print(f"Agent ID: {self.agent_id}")
        print(f"Interval: {interval_seconds} seconds")
        print(f"Repo: {self.build_repo_path}")
        print(f"Capabilities:")
        print(f"  • Execute shell commands")
        print(f"  • Read/analyze files")
        print(f"  • Run Python scripts")
        print(f"  • Git operations")
        print(f"  • System diagnostics")
        print(f"\nListening for messages with action keywords...")
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

    def get_actionable_messages(self) -> List[Dict[str, Any]]:
        """Get unread messages that require action"""
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

            # Get messages for architect that haven't been processed
            actionable = [
                msg for msg in messages_data['messages']
                if (msg['to'] == self.agent_id or msg['to'] == 'all')
                and msg['id'] not in self.processed_ids
                and not msg.get('read', False)
                and self._is_actionable(msg)
            ]

            return sorted(actionable, key=lambda x: x['timestamp'])
        except Exception as e:
            print(f"Error reading messages: {e}")
            return []

    def _is_actionable(self, message: Dict[str, Any]) -> bool:
        """Check if message contains action keywords"""
        body = message.get('body', '').lower()
        subject = message.get('subject', '').lower()
        
        action_keywords = [
            'execute', 'run', 'check', 'analyze', 'investigate',
            'debug', 'fix', 'create', 'update', 'deploy',
            'test', 'verify', 'monitor', 'scan', 'review'
        ]
        
        return any(keyword in body or keyword in subject for keyword in action_keywords)

    def execute_task(self, message: Dict[str, Any]) -> str:
        """Execute task based on message content"""
        body = message.get('body', '')
        
        print(f"\n{'='*60}")
        print(f"📋 EXECUTING TASK")
        print(f"{'='*60}")
        print(f"From: {message['from']}")
        print(f"Subject: {message['subject']}")
        print(f"Body: {body[:200]}...")
        print(f"{'='*60}\n")
        
        results = []
        
        # Parse commands from message
        # Look for code blocks or explicit commands
        if '```' in body:
            # Extract code blocks
            code_blocks = re.findall(r'```(?:\w+)?\n(.*?)```', body, re.DOTALL)
            for i, code in enumerate(code_blocks):
                results.append(f"Executing code block {i+1}:")
                result = self._execute_code(code.strip())
                results.append(result)
        
        # Look for specific action keywords
        body_lower = body.lower()
        
        if 'check status' in body_lower or 'system status' in body_lower:
            results.append(self._get_system_status())
        
        if 'git' in body_lower and ('status' in body_lower or 'diff' in body_lower):
            results.append(self._get_git_status())
        
        if 'list messages' in body_lower or 'recent messages' in body_lower:
            results.append(self._get_recent_messages())
        
        if not results:
            results.append("Task received but no executable actions identified.")
            results.append("Supported actions: check status, git status, list messages, code blocks")
        
        return "\n\n".join(results)

    def _execute_code(self, code: str) -> str:
        """Execute code safely (limited to safe operations)"""
        # For safety, only allow specific safe commands
        if code.startswith('git '):
            try:
                result = subprocess.run(
                    code,
                    shell=True,
                    cwd=self.build_repo_path,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                return f"Output:\n{result.stdout}\n{result.stderr}"
            except Exception as e:
                return f"Error executing: {e}"
        else:
            return "Code execution limited to git commands for safety. Use message actions instead."

    def _get_system_status(self) -> str:
        """Get system status"""
        status = []
        status.append("🖥️  SYSTEM STATUS:")
        status.append(f"  • Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        status.append(f"  • Agent: {self.agent_id} on CODE2 (Windows)")
        status.append(f"  • Repository: {self.build_repo_path}")
        
        # Check monitors
        try:
            result = subprocess.run(
                ["powershell", "-Command", "Get-Job -Name Code2Monitor | Select-Object State"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if "Running" in result.stdout:
                status.append("  • Monitor: ✅ Running")
            else:
                status.append("  • Monitor: ⚠️  Not running")
        except:
            status.append("  • Monitor: ❓ Unknown")
        
        return "\n".join(status)

    def _get_git_status(self) -> str:
        """Get git status"""
        try:
            result = subprocess.run(
                ["git", "status", "--short"],
                cwd=self.build_repo_path,
                capture_output=True,
                text=True
            )
            if result.stdout.strip():
                return f"📁 GIT STATUS:\n{result.stdout}"
            else:
                return "📁 GIT STATUS: Clean working tree"
        except Exception as e:
            return f"Error getting git status: {e}"

    def _get_recent_messages(self) -> str:
        """Get recent messages"""
        try:
            messages_file = self.build_repo_path / "coordination" / "messages.json"
            with open(messages_file, 'r', encoding='utf-8') as f:
                messages_data = json.load(f)
            
            recent = messages_data['messages'][-5:]
            output = ["📨 RECENT MESSAGES:"]
            for msg in recent:
                output.append(f"  • {msg['from']} → {msg['to']}: {msg['subject']}")
            return "\n".join(output)
        except Exception as e:
            return f"Error getting messages: {e}"

    def mark_processed(self, message_id: str):
        """Mark message as processed"""
        self.processed_ids.add(message_id)
        self._save_state()

    def send_response(self, original_message: Dict[str, Any], result: str):
        """Send response with task results"""
        subject = f"Re: {original_message['subject']}"
        body = f"Task completed by {self.agent_id.upper()} agent.\n\n"
        body += f"Original request from: {original_message['from']}\n"
        body += f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        body += "=" * 60 + "\n"
        body += "RESULTS:\n"
        body += "=" * 60 + "\n\n"
        body += result
        
        try:
            success = send_message(
                body=body,
                subject=subject,
                to=original_message['from'],
                from_sender=self.agent_id,
                build_repo_path=str(self.build_repo_path)
            )
            if success:
                print(f"✅ Response sent to {original_message['from']}")
            else:
                print(f"❌ Failed to send response")
        except Exception as e:
            print(f"❌ Error sending response: {e}")

    def run(self):
        """Main agent loop"""
        while True:
            try:
                messages = self.get_actionable_messages()
                
                for message in messages:
                    # Execute task
                    result = self.execute_task(message)
                    
                    # Send response
                    self.send_response(message, result)
                    
                    # Mark as processed
                    self.mark_processed(message['id'])
                
                # Sleep
                time.sleep(self.interval_seconds)
                
            except KeyboardInterrupt:
                print(f"\n\n🛑 Agent stopping...")
                break
            except Exception as e:
                print(f"❌ Error in agent loop: {e}")
                time.sleep(self.interval_seconds)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Architect Agent - Autonomous task executor")
    parser.add_argument("--interval", type=int, default=15, help="Polling interval in seconds")
    parser.add_argument("--repo", type=str, default="K:/Projects/Build", help="Build repository path")
    parser.add_argument("--agent-id", type=str, default="architect", help="Agent ID")
    
    args = parser.parse_args()
    
    agent = ArchitectAgent(
        build_repo_path=args.repo,
        interval_seconds=args.interval,
        agent_id=args.agent_id
    )
    
    agent.run()


if __name__ == "__main__":
    main()
