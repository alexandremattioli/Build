# Communication Methodology

This folder documents the communication methodology for the Build coordination system.

## Documents

### [methodology.md](methodology.md)
Complete communication methodology for the Redis-based pub/sub messaging system.

**Covers:**
- Redis pub/sub architecture (current system)
- Message structure and format
- Command reference (`sm`, `cm`)
- AI agent communication guidelines
- Response patterns and best practices
- Real-time monitoring
- Troubleshooting
- Performance metrics
- Security and privacy

**Version:** 2.0
**System:** Redis Pub/Sub (since 2025-11-13)
**Status:** ✓ Operational

## Quick Start

### Send a Message
```bash
sm all "Subject" "Message body"
sm build1 "Question" "What packages are installed?"
```

### Check Messages
```bash
cm                  # Last 10 messages
cm --last 20        # Last 20 messages
cm --watch          # Real-time monitoring
cm --stats          # System statistics
```

## Key Principles

1. **Proactive Participation** - Always contribute when you have expertise
2. **Data-Driven Responses** - Provide facts, metrics, and reasoning
3. **Real-Time Communication** - Respond within seconds, not minutes
4. **Thread Continuity** - Use "Re:" prefix to indicate replies

## Architecture

```
AI Agents → Redis PUBLISH → Redis Server → SUBSCRIBE → AI Agents
              (<10ms)      (10.1.3.74)      (Real-time)
```

**Performance:**
- Latency: <10ms
- Success Rate: 99.9%
- Agent Response: 1-2 seconds
- No conflicts, no polling

## Migration History

- **Before 2025-11-13:** Git-based messaging (deprecated)
  - 5-10 second latency
  - 40-60% failure rate
  - Constant git conflicts

- **Since 2025-11-13:** Redis pub/sub (current)
  - <10ms latency
  - 99.9% success rate
  - Zero conflicts

## Related Documentation

- [COMMUNICATION_GUIDE.md](../COMMUNICATION_GUIDE.md) - Detailed usage guide
- [REDIS_INSTALLATION.md](../REDIS_INSTALLATION.md) - Installation instructions
- [MIGRATION_SUMMARY.md](../MIGRATION_SUMMARY.md) - Complete migration details

## Support

For issues:
```bash
# Test connection
redis-cli -h 10.1.3.74 -p 6379 -a <password> ping

# View logs
tail -f /root/Build/logs/build2_redis_subscriber.log

# Send test
sm architect "Test" "Testing messaging system"
```

---

**Last Updated:** 2025-11-13
**System Status:** ✓ Operational
**Repository:** https://github.com/alexandremattioli/Build
