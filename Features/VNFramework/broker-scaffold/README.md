# VNF Broker Scaffold - README

## Overview
This is the initial broker implementation scaffold for the VNF Framework. It demonstrates:
- FastAPI REST endpoints for firewall rule operations
- Pydantic models auto-generated from JSON Schema contracts
- JWT authentication middleware (HS256 for Day-1, RS256 for production)
- Idempotency handling via client-supplied `ruleId`
- Dictionary engine stub (vendor API translation)
- Standard error taxonomy (VNF_TIMEOUT, VNF_AUTH, etc.)

## Quick Start (Development)

### Install Dependencies
```bash
cd Features/VNFramework/broker-scaffold
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Run Broker (HTTP for testing)
```bash
export BROKER_JWT_SECRET="test-secret-change-in-production"
python broker.py
# Listens on http://0.0.0.0:8443 (dev mode; production uses mTLS)
```

### Generate Test JWT
```python
import jwt
from datetime import datetime, timedelta

claims = {
    "sub": "test-user",
    "iat": datetime.utcnow(),
    "exp": datetime.utcnow() + timedelta(minutes=5),
    "scope": ["vnf:rw"]
}
token = jwt.encode(claims, "test-secret-change-in-production", algorithm="HS256")
print(f"Bearer {token}")
```

### Test Create Rule
```bash
curl -X POST http://localhost:8443/v1/firewall/rules \
  -H "Authorization: Bearer <token_from_above>" \
  -H "Content-Type: application/json" \
  -d '{
    "ruleId": "test-rule-001",
    "interface": "wan",
    "direction": "in",
    "action": "allow",
    "src": {"cidr": "any"},
    "dst": {"cidr": "192.168.1.0/24"},
    "protocol": "tcp",
    "ports": {"dst": "443"},
    "description": "Test HTTPS rule",
    "enabled": true,
    "log": true
  }'
```

Expected response:
```json
{
  "ok": true,
  "ruleId": "test-rule-001",
  "vendorRef": "pfsense-uuid-abc123",
  "appliedAt": "2025-11-04T02:20:15.123456",
  "diagnostics": {
    "latencyMs": 253,
    "retries": 0,
    "vendorLatencyMs": 250
  }
}
```

## Architecture Notes

### Security (Day-1 vs Production)
- **Day-1**: HS256 JWT with env `BROKER_JWT_SECRET`
- **Day-3+**: RS256 with keypair in `/etc/vnfbroker/jwt/{private,public}.pem`
- **mTLS**: Termination at uvicorn/nginx; client CA bundle in `/etc/vnfbroker/ca/clients/`

### Idempotency
- Client supplies `ruleId` (optional) as idempotency key
- Broker stores `(ruleId -> response)` for 24h
- Duplicate requests return cached response (no vendor call)

### Dictionary Engine
- Current: hardcoded pfSense mapping in `DictionaryEngine.execute_create_rule()`
- Next: load YAML from `/etc/vnfbroker/dictionaries/pfsense.yaml`
- Template: Jinja2 for `bodyTemplate`, JSONPath for `responseMapping`

### Error Handling
Standard codes:
- `VNF_TIMEOUT`: Vendor API timeout (retryable)
- `VNF_AUTH`: Authentication failure (not retryable)
- `VNF_CONFLICT`: Resource already exists (not retryable)
- `VNF_INVALID`: Bad request data (not retryable)
- `VNF_UPSTREAM`: Vendor 5xx error (retryable)
- `VNF_UNREACHABLE`: Connection refused (retryable)
- `VNF_CAPACITY`: Quota/rate limit (retryable with backoff)
- `BROKER_INVALID_REQUEST`: Schema validation failed
- `BROKER_INTERNAL`: Broker bug (not retryable)

## Next Steps (for Build1 review)

1. **Contract Review**
   - Confirm `CreateFirewallRuleCmd`/`Response` schemas meet DB/service layer needs
   - Validate error taxonomy aligns with retry logic requirements

2. **Dictionary Format**
   - Review `DICTIONARY_FORMAT.md` and pfSense example
   - Propose any additional fields needed (e.g., batch operations, transactions)

3. **Packaging Handoff**
   - Build1 owns final `.deb` packaging and systemd service
   - Build2 delivers: `broker.py`, `requirements.txt`, `broker.yaml.example`, `vnfbroker.service.example`

4. **Test Harness**
   - Build2 writes pytest integration tests (mock vendor responses)
   - Build1 wires into JUnit/CI for E2E validation

## Files in This Scaffold

- `broker.py`: FastAPI app with auth, idempotency, dictionary stub
- `requirements.txt`: Python dependencies
- `README.md`: This file
- `../contracts/`: JSON Schema contracts for Cmd/Response
- `../contracts/DICTIONARY_FORMAT.md`: Dictionary spec

## Configuration (Production)

`/etc/vnfbroker/broker.yaml`:
```yaml
server:
  host: 0.0.0.0
  port: 8443
  tls:
    cert: /etc/vnfbroker/tls/server.crt
    key: /etc/vnfbroker/tls/server.key
    clientCA: /etc/vnfbroker/ca/clients/ca-bundle.crt

auth:
  jwtAlgorithm: RS256
  jwtPrivateKey: /etc/vnfbroker/jwt/private.pem
  jwtPublicKey: /etc/vnfbroker/jwt/public.pem
  jwtExpiry: 300  # seconds

dictionaries:
  path: /etc/vnfbroker/dictionaries
  vendors:
    - pfsense
    - fortigate
    - paloalto
    - vyos

idempotency:
  backend: redis  # or 'memory' for dev
  ttl: 86400  # 24h in seconds
  redis:
    url: redis://localhost:6379/0

logging:
  level: INFO
  format: json
  output: /var/log/vnfbroker/broker.log
  accessLog: /var/log/vnfbroker/access.log
  redactSecrets: true

timeouts:
  connect: 3000  # ms
  read: 10000
  total: 20000

retries:
  maxAttempts: 2
  backoffMs: [100, 500]  # exponential
```

## Questions for Build1

1. **JWT preference**: OK with HS256 for Day-1 and RS256 by Day-3, or flip immediately?
2. **DB fields**: Any audit/op-hash columns we should reserve now for idempotency persistence?
3. **pfSense endpoints**: Which operations to prioritize first? (rule, NAT, route, alias?)
4. **Packaging**: Prefer Build1 owns full `.deb` or Build2 delivers draft spec?
5. **CI integration**: Maven module layout preference? (e.g., `vnf-broker/` submodule with pytest runner)

Feedback welcome—I'll iterate quickly on any contract shape changes or dictionary format tweaks.
