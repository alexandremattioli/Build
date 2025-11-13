"""
Network Connectivity Testing
Validates network connection before git operations
"""

import socket
import time
from typing import Dict, Any


def test_connectivity() -> Dict[str, Any]:
    """Test network connectivity to GitHub"""
    result = {
        "success": False,
        "message": "",
        "latency_ms": None
    }
    
    # Test DNS resolution
    try:
        socket.gethostbyname("github.com")
    except socket.gaierror as e:
        result["message"] = f"DNS resolution failed: {e}"
        return result
    
    # Test HTTPS connectivity to GitHub
    github_ip = "20.26.156.215"
    port = 443
    
    try:
        start_time = time.time()
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((github_ip, port))
        sock.close()
        latency = (time.time() - start_time) * 1000
        
        result["success"] = True
        result["message"] = "Network connectivity OK"
        result["latency_ms"] = round(latency, 2)
    except socket.timeout:
        result["message"] = f"Connection timeout to {github_ip}:{port}"
    except socket.error as e:
        result["message"] = f"Connection failed: {e}"
    
    return result
