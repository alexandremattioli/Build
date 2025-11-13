#!/usr/bin/env python3
"""
Webhook Integration for Build Infrastructure
Sends alerts to Slack, Discord, Microsoft Teams
"""

import os
import json
import requests
from typing import Dict, List, Optional
from datetime import datetime
from enum import Enum

class WebhookType(str, Enum):
    SLACK = "slack"
    DISCORD = "discord"
    TEAMS = "teams"

class WebhookManager:
    """Send alerts to various webhook endpoints"""
    
    def __init__(self, config_file: str = None):
        self.config_file = config_file or os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "shared",
            "webhook-config.json"
        )
        self.config = self._load_config()
    
    def _load_config(self) -> Dict:
        """Load webhook configuration"""
        if not os.path.exists(self.config_file):
            return {
                "slack": {"enabled": False, "webhooks": []},
                "discord": {"enabled": False, "webhooks": []},
                "teams": {"enabled": False, "webhooks": []}
            }
        
        with open(self.config_file, 'r') as f:
            return json.load(f)
    
    def send_slack_alert(
        self,
        webhook_url: str,
        title: str,
        message: str,
        severity: str = "warning",
        fields: List[Dict] = None
    ) -> bool:
        """Send Slack alert"""
        color = {
            "critical": "#f85149",
            "warning": "#d29922",
            "info": "#58a6ff",
            "success": "#3fb950"
        }.get(severity, "#8b949e")
        
        payload = {
            "attachments": [{
                "color": color,
                "title": title,
                "text": message,
                "fields": fields or [],
                "footer": "Build Infrastructure",
                "ts": int(datetime.utcnow().timestamp())
            }]
        }
        
        try:
            response = requests.post(webhook_url, json=payload, timeout=10)
            return response.status_code == 200
        except Exception as e:
            print(f"Slack webhook error: {e}")
            return False
    
    def send_discord_alert(
        self,
        webhook_url: str,
        title: str,
        message: str,
        severity: str = "warning"
    ) -> bool:
        """Send Discord alert"""
        color = {
            "critical": 16007990,  # Red
            "warning": 16766522,   # Orange
            "info": 5814783,       # Blue
            "success": 4437377     # Green
        }.get(severity, 9145227)
        
        payload = {
            "embeds": [{
                "title": title,
                "description": message,
                "color": color,
                "footer": {"text": "Build Infrastructure"},
                "timestamp": datetime.utcnow().isoformat()
            }]
        }
        
        try:
            response = requests.post(webhook_url, json=payload, timeout=10)
            return response.status_code == 204
        except Exception as e:
            print(f"Discord webhook error: {e}")
            return False
    
    def send_teams_alert(
        self,
        webhook_url: str,
        title: str,
        message: str,
        severity: str = "warning"
    ) -> bool:
        """Send Microsoft Teams alert"""
        theme_color = {
            "critical": "FF0000",
            "warning": "FFA500",
            "info": "0078D4",
            "success": "00FF00"
        }.get(severity, "808080")
        
        payload = {
            "@type": "MessageCard",
            "@context": "https://schema.org/extensions",
            "themeColor": theme_color,
            "title": title,
            "text": message
        }
        
        try:
            response = requests.post(webhook_url, json=payload, timeout=10)
            return response.status_code == 200
        except Exception as e:
            print(f"Teams webhook error: {e}")
            return False
    
    def send_alert(
        self,
        title: str,
        message: str,
        severity: str = "warning",
        webhook_type: WebhookType = None,
        fields: List[Dict] = None
    ) -> Dict[str, bool]:
        """Send alert to all enabled webhooks or specific type"""
        results = {}
        
        if webhook_type:
            types = [webhook_type]
        else:
            types = [WebhookType.SLACK, WebhookType.DISCORD, WebhookType.TEAMS]
        
        for wtype in types:
            config = self.config.get(wtype.value, {})
            if not config.get("enabled", False):
                continue
            
            for webhook_url in config.get("webhooks", []):
                if wtype == WebhookType.SLACK:
                    success = self.send_slack_alert(webhook_url, title, message, severity, fields)
                elif wtype == WebhookType.DISCORD:
                    success = self.send_discord_alert(webhook_url, title, message, severity)
                elif wtype == WebhookType.TEAMS:
                    success = self.send_teams_alert(webhook_url, title, message, severity)
                else:
                    success = False
                
                results[f"{wtype.value}_{webhook_url[:20]}"] = success
        
        return results
    
    def alert_server_offline(self, server_id: str, ip: str):
        """Alert when server goes offline"""
        self.send_alert(
            title=f"🔴 Server Offline: {server_id.upper()}",
            message=f"Server {server_id} ({ip}) is not responding.",
            severity="critical",
            fields=[
                {"title": "Server", "value": server_id, "short": True},
                {"title": "IP", "value": ip, "short": True},
                {"title": "Time", "value": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"), "short": False}
            ]
        )
    
    def alert_high_cpu(self, server_id: str, cpu_usage: float):
        """Alert when CPU usage is high"""
        self.send_alert(
            title=f"🔥 High CPU Usage: {server_id.upper()}",
            message=f"Server {server_id} CPU usage is at {cpu_usage:.1f}%",
            severity="warning",
            fields=[
                {"title": "Server", "value": server_id, "short": True},
                {"title": "CPU", "value": f"{cpu_usage:.1f}%", "short": True}
            ]
        )
    
    def alert_low_disk(self, server_id: str, disk_free_gb: int):
        """Alert when disk space is low"""
        self.send_alert(
            title=f"💾 Low Disk Space: {server_id.upper()}",
            message=f"Server {server_id} has only {disk_free_gb}GB free disk space.",
            severity="warning",
            fields=[
                {"title": "Server", "value": server_id, "short": True},
                {"title": "Free Space", "value": f"{disk_free_gb}GB", "short": True}
            ]
        )
    
    def alert_build_failed(self, server_id: str, job_id: str, branch: str):
        """Alert when build fails"""
        self.send_alert(
            title=f"❌ Build Failed: {job_id}",
            message=f"Build job {job_id} on {server_id} (branch: {branch}) has failed.",
            severity="critical",
            fields=[
                {"title": "Server", "value": server_id, "short": True},
                {"title": "Job", "value": job_id, "short": True},
                {"title": "Branch", "value": branch, "short": False}
            ]
        )


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Build Webhook Manager")
    parser.add_argument("action", choices=["test", "server-offline", "high-cpu", "low-disk", "build-failed"])
    parser.add_argument("--server", help="Server ID")
    parser.add_argument("--ip", help="Server IP")
    parser.add_argument("--cpu", type=float, help="CPU usage percentage")
    parser.add_argument("--disk", type=int, help="Disk free GB")
    parser.add_argument("--job", help="Job ID")
    parser.add_argument("--branch", help="Git branch")
    
    args = parser.parse_args()
    
    manager = WebhookManager()
    
    if args.action == "test":
        results = manager.send_alert(
            title="✅ Webhook Test",
            message="Build infrastructure webhook integration is working!",
            severity="info"
        )
        print(f"Test results: {results}")
    
    elif args.action == "server-offline":
        if not args.server or not args.ip:
            print("Error: --server and --ip required")
            exit(1)
        manager.alert_server_offline(args.server, args.ip)
        print(f"Server offline alert sent for {args.server}")
    
    elif args.action == "high-cpu":
        if not args.server or args.cpu is None:
            print("Error: --server and --cpu required")
            exit(1)
        manager.alert_high_cpu(args.server, args.cpu)
        print(f"High CPU alert sent for {args.server}")
    
    elif args.action == "low-disk":
        if not args.server or args.disk is None:
            print("Error: --server and --disk required")
            exit(1)
        manager.alert_low_disk(args.server, args.disk)
        print(f"Low disk alert sent for {args.server}")
    
    elif args.action == "build-failed":
        if not args.server or not args.job or not args.branch:
            print("Error: --server, --job, and --branch required")
            exit(1)
        manager.alert_build_failed(args.server, args.job, args.branch)
        print(f"Build failed alert sent for {args.job}")
