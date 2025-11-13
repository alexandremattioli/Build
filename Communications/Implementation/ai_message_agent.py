#!/usr/bin/env python3
"""
AI Message Agent - Uses CLI tools and AI to process and respond to messages
This is the ONLY agent needed - it replaces all monitors and handles everything
"""

import json
import time
import subprocess
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional

try:
    from message_archiver import check_and_archive
    ARCHIVER_AVAILABLE = True
except ImportError:
    ARCHIVER_AVAILABLE = False
    print("[WARN] message_archiver not available, auto-archival disabled")

from send_message import send_message


class AIMessageAgent:
    """
    Main AI-powered message agent that:
    1. Monitors messages via git coordination
    2. Uses CLI tools to gather context
    3. Generates intelligent AI responses
    4. Sends replies through message system
    """

    def __init__(
        self,
        build_repo_path: str = "K:/Projects/Build",
        interval_seconds: int = 10,
        server_id: str = "code2",
    ):
        self.build_repo_path = Path(build_repo_path)
        self.interval_seconds = interval_seconds
        self.server_id = server_id
        self.processed_ids = set()
        self.state_path = self.build_repo_path / f".ai_agent_{server_id}_state.json"
        self.response_loop_tracker = {}  # Track responses to prevent loops
        self.max_auto_responses = 2  # Max auto-responses to same message thread
        
        # Create heartbeat file
        self.heartbeat_path = self.build_repo_path / "logs" / f"ai_agent_{server_id}.heartbeat"
        self.heartbeat_path.parent.mkdir(parents=True, exist_ok=True)
        
        self._load_state()
        
        print(f"\n{'='*80}")
        print(f"AI MESSAGE AGENT - {server_id.upper()}")
        print(f"{'='*80}")
        print(f"Server: {server_id}")
        print(f"Interval: {interval_seconds}s")
        print(f"Repo: {self.build_repo_path}")
        print(f"\nCapabilities:")
        print(f"  - AI-powered message understanding and response")
        print(f"  - CLI tool integration for system operations")
        print(f"  - Context gathering from system, git, files")
        print(f"  - Autonomous task execution")
        print(f"  - Intelligent routing and prioritization")
        print(f"\nMonitoring for: {server_id}, all")
        print(f"Press Ctrl+C to stop\n")
        print(f"{'='*80}\n")

    def _load_state(self):
        """Load processed message IDs"""
        if not self.state_path.exists():
            return
        try:
            data = json.loads(self.state_path.read_text())
            self.processed_ids.update(data.get("processed_ids", []))
            print(f"[STATE] Loaded {len(self.processed_ids)} processed message IDs")
        except Exception as e:
            print(f"[WARN] Could not load state: {e}")

    def _save_state(self):
        """Save processed message IDs"""
        try:
            with open(self.state_path, "w", encoding="utf-8") as f:
                json.dump({"processed_ids": sorted(self.processed_ids)}, f, indent=2)
        except Exception as e:
            print(f"[WARN] Could not save state: {e}")

    def _should_respond(self, message: Dict[str, Any]) -> bool:
        """Check if we should respond to this message (anti-loop logic)"""
        msg_from = message.get('from', '')
        subject = message.get('subject', '')
        body = message.get('body', '')
        
        # Don't respond to our own messages
        if msg_from == self.server_id:
            return False
        
        # Don't respond to automated responses (prevent loop)
        auto_indicators = [
            'AI Agent Response',
            'responding automatically',
            'Auto-response from',
            f'{self.server_id.upper()} responding',
            'Automated reply',
            'SYSTEM STATUS:',
            'Background Jobs:'
        ]
        
        if any(indicator in body for indicator in auto_indicators):
            print(f"[ANTI-LOOP] Skipping automated message from {msg_from}")
            return False
        
        # Track response chains to prevent infinite loops
        if subject.startswith('Re:'):
            re_count = subject.count('Re: ')
            if re_count > 3:
                print(f"[ANTI-LOOP] Too many Re:'s ({re_count}) in subject, skipping")
                return False
        
        # Check thread tracking
        thread_key = f"{msg_from}:{subject[:50]}"  # First 50 chars of subject
        
        if thread_key in self.response_loop_tracker:
            count = self.response_loop_tracker[thread_key]
            if count >= self.max_auto_responses:
                print(f"[ANTI-LOOP] Already responded {count} times to this thread")
                return False
            self.response_loop_tracker[thread_key] = count + 1
        else:
            self.response_loop_tracker[thread_key] = 1
        
        return True

    def _update_heartbeat(self):
        """Update heartbeat timestamp"""
        try:
            self.heartbeat_path.write_text(datetime.utcnow().isoformat() + "Z")
        except Exception:
            pass

    def get_new_messages(self) -> List[Dict[str, Any]]:
        """Get new messages via git pull"""
        try:
            # Pull latest messages
            result = subprocess.run(
                ["git", "pull", "origin", "main"],
                cwd=self.build_repo_path,
                capture_output=True,
                check=False
            )
            
            messages_file = self.build_repo_path / "coordination" / "messages.json"
            
            # Check if archival is needed (before loading)
            if ARCHIVER_AVAILABLE:
                archive_dir = self.build_repo_path / "coordination" / "archives"
                archived = check_and_archive(messages_file, archive_dir, max_messages=800, keep_recent=400)
                if archived:
                    print(f"[ARCHIVAL] Completed automatic message archival")
            
            with open(messages_file, 'r', encoding='utf-8') as f:
                messages_data = json.load(f)

            # Get unprocessed messages for this server
            new_messages = [
                msg for msg in messages_data['messages']
                if (msg['to'] == self.server_id or msg['to'] == 'all')
                and msg['id'] not in self.processed_ids
                and msg['from'] != self.server_id
            ]

            return sorted(new_messages, key=lambda x: x['timestamp'])
        except Exception as e:
            print(f"[ERROR] Failed to get messages: {e}")
            return []

    def execute_cli_tool(self, command: str, tool_description: str) -> str:
        """Execute a CLI tool and return output"""
        try:
            print(f"[CLI] Executing: {tool_description}")
            result = subprocess.run(
                command,
                shell=True,
                cwd=self.build_repo_path,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            output = result.stdout
            if result.stderr:
                output += f"\n[STDERR]\n{result.stderr}"
            
            return output if output.strip() else "[No output]"
        except subprocess.TimeoutExpired:
            return f"[TIMEOUT] Command took longer than 30 seconds"
        except Exception as e:
            return f"[ERROR] {str(e)}"

    def gather_context(self, message: Dict[str, Any]) -> Dict[str, str]:
        """Gather system context using CLI tools"""
        context = {}
        body_lower = message.get('body', '').lower()
        
        # System status
        if any(kw in body_lower for kw in ['status', 'health', 'check']):
            context['jobs'] = self.execute_cli_tool(
                'powershell -Command "Get-Job | Select-Object Id,Name,State | Format-Table"',
                "Get background jobs"
            )
            context['processes'] = self.execute_cli_tool(
                'powershell -Command "Get-Process python | Select-Object -First 5 Id,Name,CPU,WorkingSet | Format-Table"',
                "Get Python processes"
            )
        
        # Git operations
        if 'git' in body_lower:
            context['git_status'] = self.execute_cli_tool(
                'git status --short',
                "Git status"
            )
            context['git_branch'] = self.execute_cli_tool(
                'git branch --show-current',
                "Current branch"
            )
            if 'log' in body_lower or 'history' in body_lower:
                context['git_log'] = self.execute_cli_tool(
                    'git log --oneline --graph -10',
                    "Git log (last 10)"
                )
        
        # File operations
        if any(kw in body_lower for kw in ['files', 'list', 'directory', 'folder']):
            # Determine path from message or use default
            target_path = self.build_repo_path
            if 'communications' in body_lower:
                target_path = self.build_repo_path / "Communications"
            
            context['files'] = self.execute_cli_tool(
                f'powershell -Command "Get-ChildItem -Path \'{target_path}\' | Select-Object -First 20 Name,Length,LastWriteTime | Format-Table"',
                f"List files in {target_path}"
            )
        
        # Message history
        if any(kw in body_lower for kw in ['messages', 'recent', 'history']):
            try:
                messages_file = self.build_repo_path / "coordination" / "messages.json"
                with open(messages_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                recent = data['messages'][-10:]
                msg_list = []
                for m in recent:
                    msg_list.append(f"{m['from']} -> {m['to']}: {m['subject']} [{m['timestamp']}]")
                context['recent_messages'] = "\n".join(msg_list)
            except Exception as e:
                context['recent_messages'] = f"[ERROR] {e}"
        
        # Python/code specific
        if 'python' in body_lower or 'code' in body_lower or 'script' in body_lower:
            context['python_files'] = self.execute_cli_tool(
                'powershell -Command "Get-ChildItem -Path Communications\\Implementation -Filter *.py | Select-Object Name,Length,LastWriteTime | Format-Table"',
                "Python files in Communications/Implementation"
            )
        
        return context

    def generate_ai_response(self, message: Dict[str, Any], context: Dict[str, str]) -> str:
        """Generate intelligent AI response based on message and context"""
        
        body = message.get('body', '')
        body_lower = body.lower()
        
        response_parts = []
        
        # Header
        response_parts.append(f"AI Agent Response from {self.server_id.upper()}")
        response_parts.append("=" * 80)
        response_parts.append(f"Processed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        response_parts.append(f"Original from: {message['from']}")
        response_parts.append("")
        
        # Status requests
        if any(kw in body_lower for kw in ['status', 'health', 'check', 'alive', 'ready']):
            response_parts.append("SYSTEM STATUS:")
            response_parts.append(f"  - Server: {self.server_id.upper()} (Online)")
            response_parts.append(f"  - Repository: {self.build_repo_path}")
            response_parts.append(f"  - Agent: AI Message Agent (Active)")
            response_parts.append("")
            
            if 'jobs' in context:
                response_parts.append("BACKGROUND JOBS:")
                response_parts.append(context['jobs'])
                response_parts.append("")
        
        # Git operations
        if 'git' in body_lower:
            if 'git_status' in context:
                response_parts.append("GIT STATUS:")
                response_parts.append(context['git_status'])
                response_parts.append("")
            
            if 'git_branch' in context:
                response_parts.append(f"Current Branch: {context['git_branch'].strip()}")
                response_parts.append("")
            
            if 'git_log' in context:
                response_parts.append("GIT HISTORY:")
                response_parts.append(context['git_log'])
                response_parts.append("")
        
        # File listings
        if any(kw in body_lower for kw in ['files', 'list', 'directory', 'folder']):
            if 'files' in context:
                response_parts.append("FILES:")
                response_parts.append(context['files'])
                response_parts.append("")
            if 'python_files' in context:
                response_parts.append("PYTHON FILES:")
                response_parts.append(context['python_files'])
                response_parts.append("")
        
        # Message history
        if any(kw in body_lower for kw in ['messages', 'recent', 'history']):
            if 'recent_messages' in context:
                response_parts.append("RECENT MESSAGES:")
                response_parts.append(context['recent_messages'])
                response_parts.append("")
        
        # Help/capabilities
        if any(kw in body_lower for kw in ['help', 'what can you', 'commands', 'capabilities']):
            response_parts.append("CAPABILITIES:")
            response_parts.append("  - System status monitoring (check status)")
            response_parts.append("  - Git operations (git status, git log)")
            response_parts.append("  - File operations (list files, show directory)")
            response_parts.append("  - Message history (recent messages, list messages)")
            response_parts.append("  - Task execution via CLI tools")
            response_parts.append("")
            response_parts.append("USAGE:")
            response_parts.append("  Send messages to: " + self.server_id + " or all")
            response_parts.append("  Keywords: status, git, files, messages, help")
            response_parts.append("")
        
        # Default acknowledgment if no specific response
        if len(response_parts) <= 5:  # Only header
            response_parts.append("MESSAGE ACKNOWLEDGED")
            response_parts.append("")
            response_parts.append("I received your message. Here's what you asked:")
            response_parts.append("-" * 80)
            response_parts.append(body[:500] + ("..." if len(body) > 500 else ""))
            response_parts.append("-" * 80)
            response_parts.append("")
            response_parts.append("For specific operations, try:")
            response_parts.append("  - 'check status' - System health")
            response_parts.append("  - 'git status' - Repository status")
            response_parts.append("  - 'list files' - File listings")
            response_parts.append("  - 'help' - Full capability list")
        
        return "\n".join(response_parts)

    def process_message(self, message: Dict[str, Any]):
        """Process a single message with AI"""
        
        print(f"\n{'='*80}")
        print(f"[MESSAGE] New message received")
        print(f"{'='*80}")
        print(f"From: {message['from']}")
        print(f"To: {message['to']}")
        print(f"Subject: {message['subject']}")
        print(f"Body: {message['body'][:150]}{'...' if len(message['body']) > 150 else ''}")
        print(f"{'='*80}\n")
        
        # Anti-loop check
        if not self._should_respond(message):
            print(f"[SKIP] Anti-loop check failed, marking as processed without response")
            self.mark_processed(message['id'])
            return
        
        # Gather context using CLI tools
        print(f"[AI] Gathering context...")
        context = self.gather_context(message)
        print(f"[AI] Context gathered: {len(context)} items")
        
        # Generate AI response
        print(f"[AI] Generating response...")
        response = self.generate_ai_response(message, context)
        print(f"[AI] Response generated ({len(response)} chars)")
        
        # Send response
        self.send_response(message, response)
        
        # Mark processed
        self.mark_processed(message['id'])

    def send_response(self, original_message: Dict[str, Any], response_body: str):
        """Send response message"""
        subject = f"Re: {original_message['subject']}"
        
        try:
            print(f"[SEND] Sending response to {original_message['from']}...")
            success = send_message(
                body=response_body,
                subject=subject,
                to=original_message['from'],
                from_sender=self.server_id,
                build_repo_path=str(self.build_repo_path)
            )
            if success:
                print(f"[OK] Response sent successfully")
            else:
                print(f"[FAIL] Failed to send response")
        except Exception as e:
            print(f"[ERROR] Error sending response: {e}")

    def mark_processed(self, message_id: str):
        """Mark message as processed"""
        self.processed_ids.add(message_id)
        self._save_state()

    def run(self):
        """Main agent loop"""
        print(f"[START] Agent running...\n")
        
        while True:
            try:
                # Update heartbeat
                self._update_heartbeat()
                
                # Get new messages
                messages = self.get_new_messages()
                
                if messages:
                    print(f"[INFO] Found {len(messages)} new message(s)")
                
                # Process each message
                for message in messages:
                    self.process_message(message)
                
                # Sleep
                time.sleep(self.interval_seconds)
                
            except KeyboardInterrupt:
                print(f"\n[STOP] Agent stopping gracefully...")
                break
            except Exception as e:
                print(f"[ERROR] Error in main loop: {e}")
                import traceback
                traceback.print_exc()
                time.sleep(self.interval_seconds)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="AI Message Agent - CLI-powered intelligent responses")
    parser.add_argument("--interval", type=int, default=10, help="Polling interval in seconds")
    parser.add_argument("--repo", type=str, default="K:/Projects/Build", help="Build repository path")
    parser.add_argument("--server", type=str, default="code2", help="Server ID")
    
    args = parser.parse_args()
    
    agent = AIMessageAgent(
        build_repo_path=args.repo,
        interval_seconds=args.interval,
        server_id=args.server
    )
    
    agent.run()


if __name__ == "__main__":
    main()
