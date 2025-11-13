#!/usr/bin/env python3
"""
Message Monitor - Autonomous message monitoring system
Cross-platform monitoring with auto-response and reliability features
"""

import json
import time
import subprocess
import sys
import re
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional

from circuit_breaker import CircuitBreaker
from message_queue import MessageQueue
from structured_log import StructuredLogger, LogLevel
from network_check import test_connectivity
from system_health import get_system_health
from monitoring_metrics import MetricsCollector
from send_message import send_message


class MessageMonitor:
    """Autonomous message monitoring with reliability features"""
    
    def __init__(
        self,
        build_repo_path: str = "K:/Projects/Build",
        interval_seconds: int = 10,
        server_id: str = "code2",
        log_path: Optional[str] = None,
        state_path: Optional[str] = None,
        watch_metrics_path: Optional[str] = None,
        autoresponder_metrics_path: Optional[str] = None,
        watch_heartbeat_path: Optional[str] = None,
        autoresponder_heartbeat_path: Optional[str] = None,
    ):
        self.build_repo_path = Path(build_repo_path)
        self.interval_seconds = interval_seconds
        self.server_id = server_id
        
        self.log_path = Path(log_path) if log_path else self.build_repo_path / "logs" / "watch_messages.log"
        self.state_path = Path(state_path) if state_path else self.build_repo_path / f".watch_messages_state_{server_id}.json"
        self.watch_metrics_path = Path(watch_metrics_path) if watch_metrics_path else self.build_repo_path / "logs" / "watch_metrics.json"
        self.autoresponder_metrics_path = (
            Path(autoresponder_metrics_path)
            if autoresponder_metrics_path
            else self.build_repo_path / "logs" / "autoresponder_metrics.json"
        )
        self.watch_heartbeat = Path(watch_heartbeat_path) if watch_heartbeat_path else Path("/var/run/watch_messages.heartbeat")
        self.autoresponder_heartbeat = (
            Path(autoresponder_heartbeat_path)
            if autoresponder_heartbeat_path
            else Path(f"/var/run/autoresponder_{server_id}.heartbeat")
        )

        # Initialize reliability components
        self._ensure_directories()
        self.circuit_breaker = CircuitBreaker()
        self.message_queue = MessageQueue(str(self.build_repo_path))
        self.logger = StructuredLogger(log_path=str(self.log_path), server_id=server_id)
        self.metrics = MetricsCollector(metrics_path=str(self.watch_metrics_path))
        self.autoresponder_metrics = MetricsCollector(metrics_path=str(self.autoresponder_metrics_path))
        
        self.last_message_time = time.time()
        self.last_heartbeat_time = time.time()
        self.processed_ids = set()
        self._load_state()
        
        print(f"\033[92m=== {server_id.upper()} Message Monitor Started ===\033[0m")
        print(f"Server: {server_id}")
        print(f"Interval: {interval_seconds} seconds")
        print(f"Repo: {self.build_repo_path}")
        print(f"Log: {self.log_path}")
        print(f"Watch metrics: {self.watch_metrics_path}")
        print(f"Autoresponder metrics: {self.autoresponder_metrics_path}")
        print("Reliability: Circuit breaker, message queue, health monitoring, structured logging")
        print("Press Ctrl+C to stop\n")

    def _ensure_directories(self):
        for path in {
            self.log_path.parent,
            self.watch_metrics_path.parent,
            self.autoresponder_metrics_path.parent,
            self.state_path.parent,
        }:
            try:
                path.mkdir(parents=True, exist_ok=True)
            except Exception:
                continue

    def _load_state(self):
        if not self.state_path.exists():
            return
        try:
            data = json.loads(self.state_path.read_text())
            seen = data.get("seen_ids", [])
            self.processed_ids.update(seen)
        except Exception as e:
            self.logger.warning("Failed to load processed state", {"error": str(e)})

    def _save_state(self):
        try:
            with open(self.state_path, "w", encoding="utf-8") as handle:
                json.dump({"seen_ids": sorted(self.processed_ids)}, handle, indent=2)
        except Exception as e:
            self.logger.warning("Failed to persist processed ids", {"error": str(e)})

    def _persist_processed_id(self, message_id: str) -> None:
        if not message_id or message_id in self.processed_ids:
            return
        self.processed_ids.add(message_id)
        self._save_state()

    def _write_heartbeat(self, path: Path):
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(datetime.utcnow().isoformat() + "Z", encoding="utf-8")
        except Exception as e:
            self.logger.warning("Heartbeat write failed", {"path": str(path), "error": str(e)})

    def touch_heartbeats(self):
        self._write_heartbeat(self.watch_heartbeat)
        self._write_heartbeat(self.autoresponder_heartbeat)
        self.metrics.record_operation("heartbeat", 0, True)
        self.last_heartbeat_time = time.time()

    def _record_autoresponse_metrics(self, duration_ms: float, success: bool, target: str):
        metadata = {"target": target, "component": "autoresponder"}
        self.autoresponder_metrics.record_operation("auto_response", duration_ms, success, metadata)
        self.metrics.record_operation("auto_response", duration_ms, success, metadata)
    
    def get_unread_messages(self) -> List[Dict[str, Any]]:
        """Get unread messages for this server"""
        try:
            messages_file = self.build_repo_path / "coordination" / "messages.json"
            with open(messages_file, 'r', encoding='utf-8') as f:
                messages_data = json.load(f)
            
            unread = [
                msg for msg in messages_data['messages']
                if (msg['to'] == self.server_id or msg['to'] == 'all') and
                   not msg.get('read', False) and
                   msg['from'] != self.server_id
            ]
            
            return sorted(unread, key=lambda x: x['timestamp'])
        except Exception as e:
            self.logger.error(f"Error reading messages: {e}")
            return []
    
    def mark_message_read(self, message_id: str) -> bool:
        """Mark a message as read"""
        try:
            messages_file = self.build_repo_path / "coordination" / "messages.json"
            
            with open(messages_file, 'r', encoding='utf-8') as f:
                messages_data = json.load(f)
            
            for msg in messages_data['messages']:
                if msg['id'] == message_id:
                    msg['read'] = True
                    break
            
            with open(messages_file, 'w', encoding='utf-8') as f:
                json.dump(messages_data, f, indent=2)
            
            # Commit the read status
            subprocess.run(["git", "add", "coordination/messages.json"], 
                          cwd=self.build_repo_path, check=True)
            subprocess.run(["git", "commit", "-m", f"{self.server_id}: Mark message {message_id} as read"],
                          cwd=self.build_repo_path, check=True)
            subprocess.run(["git", "push", "origin", "main"],
                          cwd=self.build_repo_path, capture_output=True)
            
            return True
        except Exception as e:
            self.logger.error(f"Error marking message read: {e}")
            return False
    
    def process_message(self, message: Dict[str, Any]):
        """Process a single message"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"\n[{timestamp}] \033[93mNEW MESSAGE\033[0m")
        print(f"From: {message['from']} | To: {message['to']} | Priority: {message.get('priority', 'normal')}")
        print(f"Subject: {message['subject']}")
        
        body_preview = message['body'][:200] if len(message['body']) > 200 else message['body']
        print(f"Body: {body_preview}...")
        
        # Check if auto-response needed
        body_lower = message.get('body','').lower()
        keywords = ['reply','respond','ready?','are you','status','report','ack','acknowledge','confirm']
        auto_response_needed = (
            any(k in body_lower for k in keywords)
            or bool(message.get('require_ack'))
            or bool(message.get('ack_required'))
        )
        if auto_response_needed:
            print("-> AUTO-RESPONDING")
            self.auto_respond(message)
        else:
            print("-> Marking as read")

        self.mark_message_read(message['id'])
        self._persist_processed_id(message.get('id', ''))
    
    def auto_respond(self, message: Dict[str, Any]) -> bool:
        """Send automatic response"""
        response_body = f"{self.server_id.upper()} (LL-{self.server_id.upper()}-02) responding automatically.\n\n"
        response_body += "Status: ONLINE and OPERATIONAL\n"
        response_body += "Systems: Python cross-platform monitor, 10s polling, heartbeat active\n"
        response_body += "Reliability: Circuit breaker, message queue, health monitoring, structured logging\n"
        response_body += "Ready for: Task assignments and coordination\n\n"
        response_body += f"Auto-response from monitor at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        
        subject = f"Re: {message['subject']}"
        try:
            start_time = time.time()
            success = send_message(
                body=response_body,
                subject=subject,
                to=message['from'],
                build_repo_path=str(self.build_repo_path)
            )
            duration_ms = (time.time() - start_time) * 1000
            
            if success:
                print("OK Auto-response sent and verified")
                self.logger.info("Auto-response sent", {
                    "to": message['from'],
                    "subject": subject,
                    "duration_ms": duration_ms,
                    "verified": True
                })
                self._record_autoresponse_metrics(duration_ms, True, message['from'])
                return True
            else:
                print("FAIL Auto-response verification failed - queueing for retry")
                self.message_queue.enqueue({
                    "body": response_body,
                    "subject": subject,
                    "to": message['from']
                })
                self._record_autoresponse_metrics(duration_ms, False, message['from'])
                return False
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000 if 'start_time' in locals() else 0
            print(f"FAIL Auto-response failed: {e}")
            self.message_queue.enqueue({
                "body": response_body,
                "subject": subject,
                "to": message['from']
            })
            self._record_autoresponse_metrics(duration_ms, False, message['from'])
            self.logger.error("Auto-response failed", {"error": str(e), "to": message['from']})
            return False
    
    def git_pull_with_retry(self) -> bool:
        """Pull latest changes with exponential backoff"""
        attempts = 0
        backoff_seconds = 2
        
        while attempts < 3:
            attempts += 1
            start_time = time.time()
            
            try:
                result = subprocess.run(
                    ["git", "pull", "origin", "main"],
                    cwd=self.build_repo_path,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                duration_ms = (time.time() - start_time) * 1000
                
                if result.returncode == 0:
                    self.circuit_breaker.record_success()
                    self.logger.info("Git pull succeeded", {
                        "attempt": attempts,
                        "duration_ms": duration_ms
                    })
                    self.metrics.record_operation("git_pull", duration_ms, True)
                    return True
                else:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Pull attempt {attempts} failed, retrying in {backoff_seconds}s...")
                    time.sleep(backoff_seconds)
                    backoff_seconds *= 2
            except Exception as e:
                self.logger.error("Git pull exception", {
                    "attempt": attempts,
                    "error": str(e)
                })
                time.sleep(backoff_seconds)
                backoff_seconds *= 2
        
        self.circuit_breaker.record_failure()
        self.logger.error("Git pull failed after retries", {"attempts": attempts})
        self.metrics.record_operation("git_pull", 0, False)
        return False
    
    def process_message_queue(self):
        """Process queued messages"""
        pending = self.message_queue.get_pending()
        
        if pending:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Processing {len(pending)} queued message(s)")
            
            for msg in pending:
                try:
                    success = send_message(
                        body=msg['body'],
                        subject=msg['subject'],
                        to=msg['to'],
                        build_repo_path=str(self.build_repo_path)
                    )
                    
                    if success:
                        self.message_queue.mark_sent(msg['id'])
                        print(f"  OK Sent queued message: {msg['subject']}")
                    else:
                        self.message_queue.increment_attempts(msg['id'])
                        print(f"  FAIL Failed to send queued message: {msg['subject']}")
                except Exception as e:
                    self.message_queue.increment_attempts(msg['id'])
                    print(f"  FAIL Error sending queued message: {e}")
    
    def check_git_lock(self):
        """Remove stale git lock if present"""
        git_lock = self.build_repo_path / ".git" / "index.lock"
        
        if git_lock.exists():
            lock_age = time.time() - git_lock.stat().st_mtime
            if lock_age > 120:  # 2 minutes
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Removing stale git lock (age: {lock_age/60:.1f} min)")
                git_lock.unlink()
    
    def run(self):
        """Main monitoring loop"""
        iteration = 0
        
        try:
            while True:
                iteration += 1
                self.touch_heartbeats()
                
                # Health check every 10 iterations
                if iteration % 10 == 0:
                    try:
                        health = get_system_health(str(self.build_repo_path))
                        if health['overall'] == 'CRITICAL':
                            print(f"[{datetime.now().strftime('%H:%M:%S')}] \033[91mCRITICAL HEALTH: {json.dumps(health)}\033[0m")
                    except Exception as e:
                        self.logger.warning(f"Health check failed: {e}")
                
                # Check circuit breaker
                if not self.circuit_breaker.can_execute():
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] \033[91mCircuit breaker OPEN - skipping git operations\033[0m")
                    time.sleep(self.interval_seconds)
                    continue
                
                # Check network connectivity
                net_check = test_connectivity()
                if not net_check['success']:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] \033[91mNetwork check failed: {net_check['message']}\033[0m")
                    self.circuit_breaker.record_failure()
                    time.sleep(self.interval_seconds)
                    continue
                
                # Check for stale git lock
                self.check_git_lock()
                
                # Pull latest changes
                if not self.git_pull_with_retry():
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Failed to pull after 3 attempts, skipping this cycle")
                    time.sleep(self.interval_seconds)
                    continue
                
                # Process message queue on successful git operation
                self.process_message_queue()
                
                # Check for unread messages
                unread = self.get_unread_messages()
                
                if unread:
                    print(f"\n=== Found {len(unread)} unread message(s) ===")
                    
                    for msg in unread:
                        if msg['id'] not in self.processed_ids:
                            try:
                                self.process_message(msg)
                                self.last_message_time = time.time()
                            except Exception as e:
                                print(f"[{datetime.now().strftime('%H:%M:%S')}] Error processing message {msg['id']}: {e}")
                                self.logger.error(f"Error processing message {msg['id']}", {"error": str(e)})
                else:
                    # Check for heartbeat (2 minutes of no messages)
                    time_since_message = time.time() - self.last_message_time
                    time_since_heartbeat = time.time() - self.last_heartbeat_time
                    
                    if time_since_message >= 120 and time_since_heartbeat >= 120:
                        print(f"[{datetime.now().strftime('%H:%M:%S')}] No messages for 2 minutes - would send heartbeat")
                        # Heartbeat implementation here if needed
                        self.last_heartbeat_time = time.time()
                        self.last_message_time = time.time()
                
                # Sleep
                time.sleep(self.interval_seconds)
                
        except KeyboardInterrupt:
            print("\n\nMonitor stopped by user")
            sys.exit(0)


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Message Monitor - Autonomous coordination")
    parser.add_argument("--interval", type=int, default=10, help="Polling interval in seconds")
    parser.add_argument("--repo", type=str, default="K:/Projects/Build", help="Build repository path")
    parser.add_argument("--server", type=str, default="code2", help="Server ID")
    parser.add_argument("--log", type=str, help="Path to structured log file")
    parser.add_argument("--state", type=str, help="Path to store processed message IDs")
    parser.add_argument("--watch-metrics", type=str, help="File to store watcher metrics")
    parser.add_argument("--autoresponder-metrics", type=str, help="File to store autoresponder metrics")
    parser.add_argument("--watch-heartbeat", type=str, help="Heartbeat file path for the watcher")
    parser.add_argument("--autoresponder-heartbeat", type=str, help="Heartbeat file path for the autoresponder")
    
    args = parser.parse_args()
    
    monitor = MessageMonitor(
        build_repo_path=args.repo,
        interval_seconds=args.interval,
        server_id=args.server,
        log_path=args.log,
        state_path=args.state,
        watch_metrics_path=args.watch_metrics,
        autoresponder_metrics_path=args.autoresponder_metrics,
        watch_heartbeat_path=args.watch_heartbeat,
        autoresponder_heartbeat_path=args.autoresponder_heartbeat,
    )
    
    monitor.run()



