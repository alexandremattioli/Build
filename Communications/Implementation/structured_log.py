"""
Structured JSON Logging
Provides consistent, parseable logging with severity levels
"""

import json
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional
from enum import Enum


class LogLevel(Enum):
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class StructuredLogger:
    """JSON structured logger with colored console output"""
    
    # ANSI color codes
    COLORS = {
        LogLevel.DEBUG: '\033[90m',      # Dark Gray
        LogLevel.INFO: '\033[36m',       # Cyan
        LogLevel.WARNING: '\033[33m',    # Yellow
        LogLevel.ERROR: '\033[91m',      # Red
        LogLevel.CRITICAL: '\033[95m',   # Magenta
    }
    RESET = '\033[0m'
    
    def __init__(self, log_path: Optional[str] = None, server_id: str = "code2"):
        self.server_id = server_id
        if log_path:
            self.log_path = Path(log_path)
        else:
            self.log_path = Path("K:/Projects/Build/code2/logs/structured.log")
        
        # Ensure log directory exists
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
    
    def log(self, level: LogLevel, message: str, metadata: Optional[Dict[str, Any]] = None):
        """Write a log entry"""
        log_entry = {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "level": level.value,
            "message": message,
            "server": self.server_id,
            "metadata": metadata or {}
        }
        
        # Write to file
        with open(self.log_path, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')
        
        # Console output with color
        color = self.COLORS.get(level, '')
        timestamp = datetime.now().strftime('%H:%M:%S')
        print(f"{color}[{timestamp}] [{level.value}] {message}{self.RESET}")
    
    def debug(self, message: str, metadata: Optional[Dict[str, Any]] = None):
        self.log(LogLevel.DEBUG, message, metadata)
    
    def info(self, message: str, metadata: Optional[Dict[str, Any]] = None):
        self.log(LogLevel.INFO, message, metadata)
    
    def warning(self, message: str, metadata: Optional[Dict[str, Any]] = None):
        self.log(LogLevel.WARNING, message, metadata)
    
    def error(self, message: str, metadata: Optional[Dict[str, Any]] = None):
        self.log(LogLevel.ERROR, message, metadata)
    
    def critical(self, message: str, metadata: Optional[Dict[str, Any]] = None):
        self.log(LogLevel.CRITICAL, message, metadata)
