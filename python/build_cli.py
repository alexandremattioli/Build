#!/usr/bin/env python3
"""
Build CLI - Command-line interface for Build infrastructure management
"""

import os
import sys
import json
import argparse
import subprocess
from datetime import datetime
from typing import Dict, List, Optional

class BuildCLI:
    """CLI tool for build infrastructure management"""
    
    def __init__(self, repo_path: str = None):
        self.repo_path = repo_path or os.getcwd()
        self.servers = ['build1', 'build2', 'build3', 'build4', 'code1', 'code2']
    
    def load_server_status(self, server_id: str) -> Dict:
        """Load status for a server"""
        status_file = os.path.join(self.repo_path, server_id, "status.json")
        if not os.path.exists(status_file):
            return {"status": "unknown", "error": "Status file not found"}
        
        with open(status_file, 'r') as f:
            return json.load(f)
    
    def cmd_status(self, args):
        """Show status of all or specific servers"""
        servers = [args.server] if args.server else self.servers
        
        print("\n" + "=" * 80)
        print("BUILD INFRASTRUCTURE STATUS")
        print("=" * 80 + "\n")
        
        for server_id in servers:
            status = self.load_server_status(server_id)
            
            status_emoji = {
                "online": "✅",
                "offline": "🔴",
                "building": "🔨",
                "idle": "💤"
            }.get(status.get("status", "unknown"), "❓")
            
            print(f"{status_emoji} {server_id.upper()}")
            print(f"  Status: {status.get('status', 'unknown')}")
            print(f"  IP: {status.get('ip', 'N/A')}")
            
            if 'system' in status:
                sys_info = status['system']
                print(f"  CPU: {sys_info.get('cpu_usage', 0):.1f}% | "
                      f"Memory: {sys_info.get('memory_used_gb', 0):.1f}GB | "
                      f"Disk Free: {sys_info.get('disk_free_gb', 0)}GB")
            
            if 'current_job' in status and status['current_job']:
                job = status['current_job']
                print(f"  Current Job: {job.get('id', 'N/A')} ({job.get('branch', 'N/A')})")
            
            print()
    
    def cmd_assign(self, args):
        """Assign a job to a server"""
        if not args.job_id or not args.server:
            print("Error: --job-id and --server required")
            return 1
        
        status = self.load_server_status(args.server)
        
        if status.get('status') == 'offline':
            print(f"❌ Cannot assign job: {args.server} is offline")
            return 1
        
        if status.get('current_job'):
            print(f"⚠️  Warning: {args.server} already has a job: {status['current_job'].get('id')}")
            if not args.force:
                print("Use --force to override")
                return 1
        
        # Update job assignment
        jobs_file = os.path.join(self.repo_path, "coordination", "jobs.json")
        with open(jobs_file, 'r') as f:
            jobs_data = json.load(f)
        
        # Find and update job
        for job in jobs_data.get('jobs', []):
            if job['id'] == args.job_id:
                job['assigned_to'] = args.server
                job['status'] = 'queued'
                break
        else:
            print(f"❌ Job {args.job_id} not found")
            return 1
        
        with open(jobs_file, 'w') as f:
            json.dump(jobs_data, f, indent=2)
        
        print(f"✅ Assigned job {args.job_id} to {args.server}")
        
        # Commit changes
        subprocess.run(['git', 'add', jobs_file], cwd=self.repo_path)
        subprocess.run(['git', 'commit', '-m', f'Assign job {args.job_id} to {args.server}'], cwd=self.repo_path)
        subprocess.run(['git', 'push', 'origin', 'main'], cwd=self.repo_path)
        
        return 0
    
    def cmd_logs(self, args):
        """View build logs for a server"""
        if not args.server:
            print("Error: --server required")
            return 1
        
        status = self.load_server_status(args.server)
        
        if 'last_build' in status and status['last_build']:
            log_file = status['last_build'].get('log')
            if log_file:
                print(f"\n📄 Log: {log_file}\n")
                print("Note: Use SSH to view actual log contents:")
                print(f"  ssh {args.server} tail -f {log_file}")
            else:
                print("❌ No log file found")
        else:
            print("❌ No build history")
        
        return 0
    
    def cmd_failover(self, args):
        """Manually trigger failover from one server to another"""
        if not args.from_server or not args.to_server:
            print("Error: --from and --to servers required")
            return 1
        
        from_status = self.load_server_status(args.from_server)
        to_status = self.load_server_status(args.to_server)
        
        if to_status.get('status') == 'offline':
            print(f"❌ Target server {args.to_server} is offline")
            return 1
        
        if from_status.get('current_job'):
            job = from_status['current_job']
            print(f"🔄 Failing over job {job.get('id')} from {args.from_server} to {args.to_server}")
            
            # Use assign command
            args.job_id = job.get('id')
            args.server = args.to_server
            args.force = True
            return self.cmd_assign(args)
        else:
            print(f"ℹ️  No active job on {args.from_server}")
        
        return 0
    
    def cmd_health(self, args):
        """Show health summary"""
        online = 0
        total = len(self.servers)
        overloaded = []
        low_disk = []
        
        for server_id in self.servers:
            status = self.load_server_status(server_id)
            
            if status.get('status') in ['online', 'idle', 'building']:
                online += 1
            
            if 'system' in status:
                sys_info = status['system']
                if sys_info.get('cpu_usage', 0) > 80:
                    overloaded.append(server_id)
                if sys_info.get('disk_free_gb', 100) < 20:
                    low_disk.append(server_id)
        
        print("\n" + "=" * 80)
        print("INFRASTRUCTURE HEALTH")
        print("=" * 80 + "\n")
        
        availability = (online / total * 100) if total > 0 else 0
        emoji = "✅" if availability == 100 else "⚠️" if availability > 50 else "🔴"
        
        print(f"{emoji} Availability: {online}/{total} servers online ({availability:.0f}%)")
        
        if overloaded:
            print(f"🔥 Overloaded: {', '.join(overloaded)}")
        
        if low_disk:
            print(f"💾 Low Disk: {', '.join(low_disk)}")
        
        if not overloaded and not low_disk and availability == 100:
            print("✨ All systems nominal")
        
        print()
        return 0


def main():
    parser = argparse.ArgumentParser(
        description="Build CLI - Manage build infrastructure from command line",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  build-cli status                      Show all servers
  build-cli status --server build1     Show specific server
  build-cli assign job123 --server build2   Assign job to server
  build-cli logs --server build1       View build logs
  build-cli failover --from build1 --to build2   Manual failover
  build-cli health                     Health summary
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Status command
    status_parser = subparsers.add_parser('status', help='Show server status')
    status_parser.add_argument('--server', choices=['build1', 'build2', 'build3', 'build4', 'code1', 'code2'])
    
    # Assign command
    assign_parser = subparsers.add_parser('assign', help='Assign job to server')
    assign_parser.add_argument('job_id', help='Job ID to assign')
    assign_parser.add_argument('--server', required=True)
    assign_parser.add_argument('--force', action='store_true', help='Force assignment even if server is busy')
    
    # Logs command
    logs_parser = subparsers.add_parser('logs', help='View build logs')
    logs_parser.add_argument('--server', required=True)
    logs_parser.add_argument('--follow', '-f', action='store_true', help='Follow log output')
    
    # Failover command
    failover_parser = subparsers.add_parser('failover', help='Trigger manual failover')
    failover_parser.add_argument('--from', dest='from_server', required=True, help='Source server')
    failover_parser.add_argument('--to', dest='to_server', required=True, help='Target server')
    
    # Health command
    health_parser = subparsers.add_parser('health', help='Show infrastructure health')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 0
    
    cli = BuildCLI()
    
    if args.command == 'status':
        return cli.cmd_status(args)
    elif args.command == 'assign':
        return cli.cmd_assign(args)
    elif args.command == 'logs':
        return cli.cmd_logs(args)
    elif args.command == 'failover':
        return cli.cmd_failover(args)
    elif args.command == 'health':
        return cli.cmd_health(args)
    else:
        print(f"Unknown command: {args.command}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
