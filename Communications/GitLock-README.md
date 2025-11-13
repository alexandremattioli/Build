# Git Lock Mechanism

## Problem
Both CODE2 and BUILD1 monitors were committing to `coordination/messages.json` simultaneously, causing:
- Git merge conflicts
- JSON corruption  
- Failed message sends

## Solution: GitLock Class

### How It Works
1. **File-based lock**: Creates `.git_lock` file in repo root
2. **Exclusive creation**: Uses `touch(exist_ok=False)` - only succeeds if file doesn't exist
3. **Timeout protection**: 30-second timeout prevents deadlocks
4. **Stale lock cleanup**: Locks older than 60 seconds are automatically removed
5. **Exponential backoff**: Wait time increases: 0.1s → 0.2s → 0.4s → ... up to 5s
6. **Random jitter**: Adds 0-0.5s randomness to prevent synchronized retries

### Lock Lifecycle
```python
with GitLock(repo_path) as lock:
    # 1. Pull latest
    git pull origin main
    
    # 2. Modify messages.json
    # ... add message ...
    
    # 3. Commit and push (with retry)
    git add coordination/messages.json
    git commit -m "..."
    git push origin main  # Retries up to 3 times
```

### Benefits
- **Prevents conflicts**: Only one process can commit at a time
- **Auto-recovery**: Handles network failures with retry logic
- **No deadlocks**: Timeout ensures locks are eventually released
- **Fair access**: Random jitter prevents starvation

### Lock File Location
- CODE2: `K:\Projects\Build\.git_lock`
- BUILD1: `/root/Build/.git_lock`

**Note**: The lock file is temporary and automatically cleaned up. If a process crashes, the lock will be cleared after 60 seconds.
