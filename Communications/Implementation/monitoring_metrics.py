"""
Performance Metrics Collection
Tracks and aggregates monitoring performance metrics
"""

import json
import time
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime, timedelta


class MetricsCollector:
    """Collect and aggregate performance metrics"""
    
    def __init__(self, build_repo_path: Optional[str] = None, metrics_path: Optional[str] = None):
        if metrics_path:
            self.metrics_path = Path(metrics_path)
        elif build_repo_path:
            self.metrics_path = Path(build_repo_path) / "code2" / "logs" / "metrics.json"
        else:
            raise ValueError("Either build_repo_path or metrics_path must be provided")
        self.metrics_path.parent.mkdir(parents=True, exist_ok=True)
        self._ensure_metrics_exist()
    
    def _ensure_metrics_exist(self):
        """Ensure metrics file exists"""
        if not self.metrics_path.exists():
            self._save_metrics({
                "operations": [],
                "summary": {
                    "messages_processed": 0,
                    "messages_received": 0,
                    "messages_sent": 0,
                    "auto_responses": 0,
                    "errors": 0,
                    "git_pull_successes": 0,
                    "git_pull_failures": 0,
                    "heartbeats_sent": 0
                }
            })
    
    def _load_metrics(self) -> Dict[str, Any]:
        """Load metrics from disk"""
        try:
            with open(self.metrics_path, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, FileNotFoundError):
            return {"operations": [], "summary": {}}
    
    def _save_metrics(self, metrics: Dict[str, Any]):
        """Save metrics to disk"""
        with open(self.metrics_path, 'w') as f:
            json.dump(metrics, f, indent=2)
    
    def record_operation(self, operation_type: str, duration_ms: float, success: bool, metadata: Optional[Dict[str, Any]] = None):
        """Record an operation metric"""
        metrics = self._load_metrics()

        operation = {
            "timestamp": time.time(),
            "type": operation_type,
            "duration_ms": duration_ms,
            "success": success,
            "metadata": metadata or {}
        }

        # Ensure operations list exists
        if "operations" not in metrics:
            metrics["operations"] = []
        
        metrics["operations"].append(operation)        # Update summary
        summary = metrics.get("summary", {})
        
        if operation_type == "message_processed":
            summary["messages_processed"] = summary.get("messages_processed", 0) + 1
        elif operation_type == "message_received":
            summary["messages_received"] = summary.get("messages_received", 0) + 1
        elif operation_type == "message_sent":
            summary["messages_sent"] = summary.get("messages_sent", 0) + 1
        elif operation_type == "auto_response":
            summary["auto_responses"] = summary.get("auto_responses", 0) + 1
        elif operation_type == "error":
            summary["errors"] = summary.get("errors", 0) + 1
        elif operation_type == "git_pull":
            if success:
                summary["git_pull_successes"] = summary.get("git_pull_successes", 0) + 1
            else:
                summary["git_pull_failures"] = summary.get("git_pull_failures", 0) + 1
        elif operation_type == "heartbeat":
            summary["heartbeats_sent"] = summary.get("heartbeats_sent", 0) + 1
        
        metrics["summary"] = summary
        
        # Keep only last 1000 operations
        if len(metrics["operations"]) > 1000:
            metrics["operations"] = metrics["operations"][-1000:]
        
        self._save_metrics(metrics)
    
    def get_summary(self, hours: int = 24) -> Dict[str, Any]:
        """Get metrics summary for last N hours"""
        metrics = self._load_metrics()
        cutoff_time = time.time() - (hours * 3600)
        
        recent_ops = [op for op in metrics["operations"] if op["timestamp"] > cutoff_time]
        
        # Calculate average response time
        response_times = [op["duration_ms"] for op in recent_ops if op["type"] == "auto_response" and op["success"]]
        avg_response_time = sum(response_times) / len(response_times) if response_times else 0
        
        return {
            "period_hours": hours,
            "total_operations": len(recent_ops),
            "summary": metrics.get("summary", {}),
            "avg_response_time_ms": round(avg_response_time, 2)
        }
