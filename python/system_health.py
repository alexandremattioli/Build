"""
System Health Monitoring
Monitors system resources and git repository health
"""

import shutil
import psutil
import subprocess
from pathlib import Path
from typing import Dict, Any


def get_system_health(build_repo_path: str) -> Dict[str, Any]:
    """Check system health metrics"""
    repo_path = Path(build_repo_path)
    
    health = {
        "overall": "HEALTHY",
        "checks": {}
    }
    
    # Disk space check
    try:
        disk_usage = shutil.disk_usage(repo_path)
        free_gb = disk_usage.free / (1024**3)
        
        if free_gb < 0.5:
            health["checks"]["disk_space"] = {"status": "CRITICAL", "free_gb": round(free_gb, 2)}
            health["overall"] = "CRITICAL"
        elif free_gb < 1.0:
            health["checks"]["disk_space"] = {"status": "WARNING", "free_gb": round(free_gb, 2)}
            if health["overall"] != "CRITICAL":
                health["overall"] = "WARNING"
        else:
            health["checks"]["disk_space"] = {"status": "OK", "free_gb": round(free_gb, 2)}
    except Exception as e:
        health["checks"]["disk_space"] = {"status": "ERROR", "error": str(e)}
        health["overall"] = "WARNING"
    
    # Memory check
    try:
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        
        if memory_percent > 95:
            health["checks"]["memory"] = {"status": "WARNING", "used_percent": memory_percent}
            if health["overall"] not in ["CRITICAL"]:
                health["overall"] = "WARNING"
        else:
            health["checks"]["memory"] = {"status": "OK", "used_percent": memory_percent}
    except Exception as e:
        health["checks"]["memory"] = {"status": "ERROR", "error": str(e)}
    
    # Git repository check
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            health["checks"]["git_repo"] = {"status": "OK", "uncommitted": len(result.stdout.splitlines())}
        else:
            health["checks"]["git_repo"] = {"status": "WARNING", "error": "Git status failed"}
            if health["overall"] not in ["CRITICAL"]:
                health["overall"] = "WARNING"
    except Exception as e:
        health["checks"]["git_repo"] = {"status": "ERROR", "error": str(e)}
    
    return health
