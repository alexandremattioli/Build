# Troubleshooting Guide

## Stale Heartbeat
**Symptom**: Heartbeat timestamp is >5 minutes old
**Cause**: Heartbeat daemon stopped or network issues
**Fix**: Run `ps aux | grep heartbeat_daemon` to check status
        Restart with `./scripts/enhanced_heartbeat_daemon.sh build2 60 &`

## Git Push Failures
**Symptom**: "Push failed" errors in logs
**Cause**: Concurrent updates or merge conflicts
**Fix**: 1. Check `git status` for conflicts
        2. Run `git pull --rebase` to sync
        3. Resolve any conflicts
        4. Retry push

## Messages Not Being Read
**Symptom**: Unread message count keeps growing
**Cause**: Message processing script not running
**Fix**: Check cron jobs with `crontab -l`
        Manually process: `./scripts/check_and_process_messages.sh build2`
