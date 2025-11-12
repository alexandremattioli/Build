# VNF Framework Quick Start Guide

**Build2 - Phase 1 Deliverables Testing**  
**Last Updated**: 2025-11-07 19:30 UTC  
**Status**: Ready for Build1 Integration Testing

---

## 🚀 One-Command Setup

```bash
cd /Builder2/Build/Features/VNFramework
./quickstart.sh
```

This will:
1. [OK] Check prerequisites (Python 3, Redis/Docker)
2. [OK] Install Python dependencies from requirements.txt
3. [OK] Start Redis (Docker container or system service)
4. [OK] Start VNF Broker on https://localhost:8443
5. [OK] Start Mock VNF Server on http://localhost:9443
6. [OK] Display service status
7. ❓ Optionally run integration tests

---

## � Containerized Setup (Docker Compose)

If you prefer containers, a compose stack is included to run Redis, the Broker, and the Mock VNF together.

```bash
cd /Builder2/Build/Features/VNFramework
docker compose up -d

# Check status
docker compose ps

# Tail broker logs
docker compose logs -f broker

# Tear down
docker compose down
```

Notes:
- The compose stack builds two local images:
  - `broker`: from `python-broker/Dockerfile`
  - `mock-vnf`: from `testing/Dockerfile`
- It also starts `redis:7-alpine` and wires the network automatically.
- The broker mounts `python-broker/keys` (read-only) and `config.dev.json`. Ensure `python-broker/keys/jwt_public.pem` exists.
- After starting, verify:
  - `curl -k https://localhost:8443/health` (broker)
  - `curl http://localhost:9443/mock/status` (mock VNF)

---

## �[i] Prerequisites

### Required
- **Python 3.11+** (3.8+ minimum)
- **Redis 5.0+** OR **Docker** (for Redis container)
- **pip** (Python package manager)

### Install on Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip redis-server

# OR use Docker for Redis
sudo apt-get install -y docker.io
sudo systemctl start docker
```

### Python Dependencies (auto-installed by quickstart.sh)
```
flask>=2.3.0
redis>=5.0.0
pyjwt>=2.8.0
cryptography>=41.0.0
pydantic>=2.0.0
jsonschema>=4.19.0
pyyaml>=6.0
requests>=2.31.0
```

---

## 🎯 Usage Scenarios

### Scenario 1: Full Development Environment
**Start everything and run tests**
```bash
./quickstart.sh
# When prompted: y (to run tests)
```

**Result:**
- Redis running (Docker or system)
- Broker at https://localhost:8443
- Mock VNF at http://localhost:9443
- Integration tests executed

---

### Scenario 2: Broker Development
**Start only broker (for API development)**
```bash
./quickstart.sh --broker-only
```

**Result:**
- Redis running
- Broker at https://localhost:8443
- No mock VNF (manual VNF testing)

**Use Case:** Testing broker with real pfSense appliance

---

### Scenario 3: Integration Testing
**Run tests against running services**
```bash
# First, start services
./quickstart.sh --broker-only

# In another terminal, start mock VNF
cd testing
python3 mock_vnf_server.py --vendor pfsense --port 9443

# Run tests
./quickstart.sh --test-only
```

**Result:** Tests run without restarting services

---

### Scenario 4: Service Management
**Check status of all services**
```bash
./quickstart.sh --status
```

**Output:**
```
========================================
VNF Framework Service Status
========================================
Redis:      [OK] Running
Broker:     [OK] Running (PID: 12345)
Mock VNF:   [OK] Running (PID: 12346)
========================================

Broker URLs:
  Health:  https://localhost:8443/health
  Metrics: https://localhost:8443/metrics
  API:     https://localhost:8443/api/vnf/*

Mock VNF URLs:
  Health:  http://localhost:9443/health
  Status:  http://localhost:9443/mock/status
  Rules:   http://localhost:9443/mock/rules
```

**Stop all services:**
```bash
./quickstart.sh --stop
```

---

## 🔧 Manual Setup (Alternative)

### Step 1: Start Redis
```bash
# Option A: Docker
docker run -d --name vnf-redis -p 6379:6379 redis:7-alpine

# Option B: System Service
sudo systemctl start redis-server

# Verify
redis-cli ping  # Should return PONG
```

### Step 2: Install Python Dependencies
```bash
cd python-broker
pip3 install -r requirements.txt
```

### Step 3: Configure JWT Public Key
```bash
# Ensure Build1's public key is in place
ls -la python-broker/keys/jwt_public.pem

# If missing, request from Build1
# Expected location: /Builder2/Build/Features/VNFramework/python-broker/keys/jwt_public.pem
```

### Step 4: Start VNF Broker
```bash
cd python-broker
python3 vnf_broker_enhanced.py

# Or run in background
nohup python3 vnf_broker_enhanced.py > /tmp/vnf-broker.log 2>&1 &

# Check logs
tail -f /tmp/vnf-broker.log
```

### Step 5: Start Mock VNF (Testing Only)
```bash
cd testing
python3 mock_vnf_server.py --vendor pfsense --port 9443

# Or in background
nohup python3 mock_vnf_server.py --vendor pfsense --port 9443 > /tmp/mock-vnf.log 2>&1 &
```

### Step 6: Run Tests
```bash
cd testing

# Without authentication (auth tests will fail)
python3 integration_test.py

# With JWT token (requires Build1's private key or token)
python3 integration_test.py --jwt-token <token>

# Or use client to generate token
cd ../clients/python
python3 vnf_broker_client.py --generate-token --private-key /path/to/private.pem
```

---

## 🧪 Testing Endpoints

### Broker Health Check
```bash
curl -k https://localhost:8443/health
```

**Expected Response:**
```json
{
  "status": "healthy",
  "redis": "connected",
  "timestamp": "2025-11-07T19:30:00Z"
}
```

### Broker Metrics
```bash
curl -k https://localhost:8443/metrics
```

**Expected Response:**
```json
{
  "circuit_breaker": {
    "instance_10.0.0.1": {
      "state": "closed",
      "failures": 0,
      "last_failure": null
    }
  },
  "rate_limits": {
    "client_192.168.1.10": {
      "requests": 45,
      "window_start": "2025-11-07T19:25:00Z"
    }
  }
}
```

### Mock VNF Status
```bash
curl http://localhost:9443/mock/status
```

**Expected Response:**
```json
{
  "vendor": "pfsense",
  "firewall_rules": 0,
  "nat_rules": 0,
  "uptime_seconds": 120,
  "error_rate": 0.0,
  "latency_ms": 50
}
```

### Create Firewall Rule (with JWT)
```bash
# First, get JWT token from Build1 or generate with client
TOKEN="<your-jwt-token>"

curl -k -X POST https://localhost:8443/api/vnf/firewall/create \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnf_instance_id": "10.0.0.1",
    "rule": {
      "action": "allow",
      "protocol": "tcp",
      "source_cidr": "192.168.1.0/24",
      "dest_cidr": "10.0.0.0/8",
      "dest_port": 443
    },
    "idempotency_key": "test-rule-001"
  }'
```

**Expected Response (202 Accepted):**
```json
{
  "request_id": "req_abc123",
  "vnf_instance_id": "10.0.0.1",
  "rule_id": "fw_rule_xyz789",
  "status": "accepted",
  "idempotency_key": "test-rule-001"
}
```

---

## 📁 File Locations

### Configuration
- **Broker Config**: `python-broker/config.dev.json`
- **JWT Public Key**: `python-broker/keys/jwt_public.pem` *(from Build1)*
- **Dictionary Schema**: `schemas/vnf-dictionary-schema.json`
- **Sample Dictionaries**: `dictionaries/pfsense-v1.yaml`, `dictionaries/fortinet-v1.yaml`

### Logs (when run with quickstart.sh)
- **Broker**: `/tmp/vnf-broker.log`
- **Mock VNF**: `/tmp/mock-vnf.log`

### Documentation
- **API Spec**: `openapi/vnf-broker-api.yaml`
- **Versioning**: `docs/DICTIONARY_VERSIONING.md`
- **Deliverables**: `PHASE1_DELIVERABLES.md`
- **README**: `README.md`

---

## 🐛 Troubleshooting

### Issue: Redis Connection Failed
**Symptom:** Broker logs show `redis.exceptions.ConnectionError`

**Solution:**
```bash
# Check if Redis is running
redis-cli ping

# Start Redis if not running
./quickstart.sh --broker-only  # Auto-starts Redis

# OR manually
docker run -d --name vnf-redis -p 6379:6379 redis:7-alpine
```

---

### Issue: JWT Public Key Not Found
**Symptom:** `FileNotFoundError: keys/jwt_public.pem`

**Solution:**
```bash
# Check if key exists
ls -la python-broker/keys/jwt_public.pem

# If missing, request from Build1
# Build1 should have sent this in msg_1762504862
# Key should be 800 bytes, RS256 algorithm

# Verify key format (should start with -----BEGIN PUBLIC KEY-----)
head -2 python-broker/keys/jwt_public.pem
```

---

### Issue: Port Already in Use
**Symptom:** `OSError: [Errno 98] Address already in use`

**Solution:**
```bash
# Check what's using port 8443
sudo lsof -i :8443

# Kill existing broker process
pkill -f vnf_broker_enhanced.py

# Or use different port (edit config.dev.json)
{
  "BROKER_PORT": 8444  # Change from 8443
}
```

---

### Issue: Mock VNF Not Responding
**Symptom:** `curl: (7) Failed to connect to localhost port 9443`

**Solution:**
```bash
# Check if mock VNF is running
pgrep -f mock_vnf_server.py

# Check logs
tail -20 /tmp/mock-vnf.log

# Restart mock VNF
cd testing
python3 mock_vnf_server.py --vendor pfsense --port 9443
```

---

### Issue: Integration Tests Failing
**Symptom:** `401 Unauthorized` errors in tests

**Solution:**
```bash
# Tests require valid JWT token
# Option A: Skip auth tests
python3 integration_test.py  # Auth tests will fail, others pass

# Option B: Generate token with Build1's private key
cd clients/python
python3 vnf_broker_client.py --generate-token --private-key /path/to/jwt_private.pem

# Option C: Get token from Build1
# Request a test token from Build1's DAO authentication service
```

---

### Issue: SSL Certificate Warnings
**Symptom:** `SSL: CERTIFICATE_VERIFY_FAILED`

**Solution:**
```bash
# Development mode uses self-signed certificates
# Use -k flag with curl
curl -k https://localhost:8443/health

# In Python clients
import requests
requests.get('https://localhost:8443/health', verify=False)

# For production, generate proper certificates:
# See deployment/tls-config.md
```

---

## 🔐 Security Notes

### Development Mode (Current)
- **Self-signed TLS certificates** (not for production)
- **JWT public key** from Build1 (RS256 algorithm)
- **Rate limiting**: 100 requests/60 seconds per client
- **Circuit breaker**: 5 failures → 30 second timeout

### Production Checklist (Phase 2)
- [ ] Replace self-signed certificates with CA-signed certs
- [ ] Implement JWT key rotation (24-hour TTL)
- [ ] Tune rate limits based on load testing
- [ ] Enable TLS 1.3 only
- [ ] Add request logging and audit trail
- [ ] Configure firewall rules (allow only CloudStack IPs)
- [ ] Enable Redis authentication
- [ ] Set up monitoring and alerting

---

## 📊 Service URLs Reference

| Service | URL | Purpose |
|---------|-----|---------|
| **Broker Health** | https://localhost:8443/health | Health check |
| **Broker Metrics** | https://localhost:8443/metrics | Circuit breaker & rate limit stats |
| **Firewall API** | https://localhost:8443/api/vnf/firewall/create | Create firewall rules |
| **NAT API** | https://localhost:8443/api/vnf/nat/create | Create NAT rules |
| **Mock VNF Health** | http://localhost:9443/health | Mock VNF health |
| **Mock VNF Status** | http://localhost:9443/mock/status | Rule counts, uptime |
| **Mock VNF Rules** | http://localhost:9443/mock/rules | List all rules |
| **Mock VNF Config** | http://localhost:9443/mock/config | Set error rate, latency |
| **Mock VNF Reset** | http://localhost:9443/mock/reset | Clear all rules |

---

## 🎓 Next Steps

### For Build1 Integration
1. [OK] Run `./quickstart.sh` to verify all components work
2. [OK] Test broker health and metrics endpoints
3. [OK] Review OpenAPI spec: `openapi/vnf-broker-api.yaml`
4. ⏳ Provide pfSense lab credentials for real-world testing
5. ⏳ Review Phase 1 deliverables: `PHASE1_DELIVERABLES.md`
6. ⏳ Coordinate Phase 2 kickoff (DAO integration, additional operations)

### For Local Development
1. Start with mock VNF: `./quickstart.sh`
2. Explore API with Swagger UI: See `ui-specs/swagger-integration.md`
3. Test client library: `clients/python/vnf_broker_client.py`
4. Validate dictionaries: `python3 schemas/dictionary_validator.py --dev dictionaries/pfsense-v1.yaml`
5. Check version compatibility: `python3 schemas/version_checker.py`

### For Phase 2 Preparation
- Review potential enhancements in `PHASE1_DELIVERABLES.md` (Section 9)
- Set up actual pfSense instance (waiting for lab access)
- Performance testing with JMeter or Locust
- Security audit and hardening
- Add UPDATE/DELETE operations for firewall rules

---

## 📞 Support

**Build2 Contact**: Via Build coordination messages  
**Last Status Update**: msg_1762541777 (2025-11-07 19:10 UTC)  
**Phase 1 Status**: [OK] Complete (12/12 tasks, 4,150+ lines)  
**Phase 2 Status**: ⏳ Awaiting Build1 coordination

---

**Quick Command Reference:**
```bash
# Start everything
./quickstart.sh

# Check status
./quickstart.sh --status

# Stop everything
./quickstart.sh --stop

# Broker logs
tail -f /tmp/vnf-broker.log

# Mock VNF logs
tail -f /tmp/mock-vnf.log

# Health check
curl -k https://localhost:8443/health
```

🚀 **Ready to test!**
