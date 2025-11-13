#!/usr/bin/env python3
"""
Message Archiver - Archives old messages to prevent file bloat
"""

import json
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any


def archive_old_messages(
    messages_file: Path,
    archive_dir: Path,
    keep_recent: int = 500,
    backup: bool = True
) -> Dict[str, Any]:
    """
    Archive old messages, keeping only recent ones
    
    Args:
        messages_file: Path to messages.json
        archive_dir: Directory to store archives
        keep_recent: Number of recent messages to keep
        backup: Whether to create a backup before archiving
    
    Returns:
        Dict with archival statistics
    """
    
    archive_dir.mkdir(parents=True, exist_ok=True)
    
    stats = {
        "original_count": 0,
        "archived_count": 0,
        "kept_count": 0,
        "archive_file": None,
        "success": False
    }
    
    try:
        # Load messages
        with open(messages_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        messages = data.get('messages', [])
        stats['original_count'] = len(messages)
        
        if len(messages) <= keep_recent:
            print(f"[INFO] Only {len(messages)} messages, no archival needed")
            stats['kept_count'] = len(messages)
            stats['success'] = True
            return stats
        
        # Backup original if requested
        if backup:
            backup_file = messages_file.with_suffix('.json.backup')
            shutil.copy2(messages_file, backup_file)
            print(f"[BACKUP] Created {backup_file}")
        
        # Split messages
        to_archive = messages[:-keep_recent]
        to_keep = messages[-keep_recent:]
        
        # Create archive file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        archive_file = archive_dir / f"messages_archive_{timestamp}.json"
        
        # Save archived messages
        with open(archive_file, 'w', encoding='utf-8') as f:
            json.dump({
                "archived_at": datetime.now().isoformat() + "Z",
                "original_file": str(messages_file),
                "message_count": len(to_archive),
                "date_range": {
                    "oldest": to_archive[0].get('timestamp') if to_archive else None,
                    "newest": to_archive[-1].get('timestamp') if to_archive else None
                },
                "messages": to_archive
            }, f, indent=2)
        
        print(f"[ARCHIVE] Saved {len(to_archive)} messages to {archive_file}")
        
        # Save reduced message file
        with open(messages_file, 'w', encoding='utf-8') as f:
            json.dump({"messages": to_keep}, f, indent=2)
        
        print(f"[SAVE] Kept {len(to_keep)} recent messages in {messages_file}")
        
        stats['archived_count'] = len(to_archive)
        stats['kept_count'] = len(to_keep)
        stats['archive_file'] = str(archive_file)
        stats['success'] = True
        
    except Exception as e:
        print(f"[ERROR] Archival failed: {e}")
        stats['error'] = str(e)
    
    return stats


def check_and_archive(
    messages_file: Path,
    archive_dir: Path,
    max_messages: int = 800,
    keep_recent: int = 500
) -> bool:
    """
    Check if archival is needed and perform it
    
    Args:
        messages_file: Path to messages.json
        archive_dir: Directory for archives
        max_messages: Trigger archival when count exceeds this
        keep_recent: Number of messages to keep after archival
    
    Returns:
        True if archival was performed, False otherwise
    """
    
    try:
        with open(messages_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        message_count = len(data.get('messages', []))
        
        if message_count > max_messages:
            print(f"[ARCHIVAL] Message count {message_count} exceeds {max_messages}, archiving...")
            stats = archive_old_messages(messages_file, archive_dir, keep_recent)
            
            if stats['success']:
                print(f"[SUCCESS] Archived {stats['archived_count']}, kept {stats['kept_count']}")
                return True
            else:
                print(f"[FAILED] Archival did not complete successfully")
                return False
        
        return False
        
    except Exception as e:
        print(f"[ERROR] Could not check/archive: {e}")
        return False


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python message_archiver.py <repo_path> [keep_recent]")
        sys.exit(1)
    
    repo_path = Path(sys.argv[1])
    keep_recent = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    
    messages_file = repo_path / "coordination" / "messages.json"
    archive_dir = repo_path / "coordination" / "archives"
    
    print(f"Archiving messages from: {messages_file}")
    print(f"Archive directory: {archive_dir}")
    print(f"Keeping recent: {keep_recent}")
    print()
    
    stats = archive_old_messages(messages_file, archive_dir, keep_recent)
    
    print()
    print("ARCHIVAL SUMMARY:")
    print(f"  Original count: {stats['original_count']}")
    print(f"  Archived count: {stats['archived_count']}")
    print(f"  Kept count: {stats['kept_count']}")
    print(f"  Archive file: {stats.get('archive_file', 'N/A')}")
    print(f"  Success: {stats['success']}")
