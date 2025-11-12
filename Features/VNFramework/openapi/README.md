# VNF Broker API Documentation

## Overview

The VNF (Virtual Network Function) Broker is a production-ready API gateway that sits between CloudStack Management Server and vendor VNF appliances (pfSense, FortiGate, etc.). It provides:

- **Vendor Abstraction**: YAML-based dictionaries for each vendor
- **Idempotency**: Redis-backed caching with 24h TTL
- **Security**: RS256 JWT authentication
- **Reliability**: Rate limiting and circuit breaker patterns
- **Validation**: Pydantic request validation
- **Observability**: Health and metrics endpoints

**Build2 Implementation** - Per coordination msg_1762504317

---

## Quick Start

### 1. Install Dependencies

```bash
cd python-broker
pip install -r requirements.txt
```

### 2. Configure Broker

Copy and edit the development config:

```bash
cp config.sample.json config.dev.json
# Edit config.dev.json with your settings
```

**Key settings:**
- `JWT_PUBLIC_KEY_PATH`: Path to RS256 public key from CloudStack
- `REDIS_HOST/PORT`: Redis server for idempotency and rate limiting
- `RATE_LIMIT_REQUESTS`: Max requests per window (default: 100/60s)
- `CIRCUIT_BREAKER_THRESHOLD`: Failures before opening (default: 5)

### 3. Start Redis

```bash
# Docker
docker run -d -p 6379:6379 redis:7-alpine

# Or system Redis
sudo systemctl start redis
```

### 4. Run Broker

```bash
# Development mode
python3 vnf_broker_enhanced.py

# Production (with gunicorn)
gunicorn -w 4 -b 0.0.0.0:8443 --certfile=/etc/vnf-broker/server.crt --keyfile=/etc/vnf-broker/server.key vnf_broker_enhanced:app
```

---

## API Reference

### Authentication

All endpoints (except `/health` and `/metrics`) require RS256 JWT authentication.

```
Authorization: Bearer <jwt_token>
```

**JWT Claims:**
- `sub`: Subject (e.g., "cloudstack-management")
- `iat`: Issued at timestamp
- `exp`: Expiration timestamp

### Endpoints

#### Health Check

```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "vnf-broker-enhanced",
  "version": "1.0.0-build2",
  "redis": {
    "status": "connected",
    "latency_ms": 2
  },
  "timestamp": "2025-11-07T18:30:00Z"
}
```

#### Metrics

```http
GET /metrics
```

**Response:**
```json
{
  "circuit_breakers": {
    "vnf-pfsense-001": {
      "state": "closed",
      "failure_count": 0
    }
  },
  "timestamp": "2025-11-07T18:30:00Z"
}
```

#### Create Firewall Rule

```http
POST /api/vnf/firewall/create
Content-Type: application/json
Authorization: Bearer <token>

{
  "vnfInstanceId": "vnf-pfsense-001",
  "ruleId": "fw-rule-12345",
  "action": "allow",
  "protocol": "tcp",
  "sourceIp": "10.0.0.0/24",
  "destinationIp": "192.168.1.0/24",
  "destinationPort": 443,
  "enabled": true,
  "description": "Allow HTTPS traffic"
}
```

**Response (201 Created):**
```json
{
  "success": true,
  "ruleId": "fw-rule-12345",
  "vnfInstanceId": "vnf-pfsense-001",
  "status": "created",
  "timestamp": "2025-11-07T18:30:00Z",
  "request_id": "a1b2c3d4"
}
```

**Idempotency:** Identical requests return cached response (200 OK) with same payload.

**Error Responses:**
- `400`: Validation error (invalid request data)
- `401`: Unauthorized (missing/invalid Authorization header)
- `403`: Forbidden (invalid/expired JWT)
- `429`: Rate limit exceeded (retry after N seconds)
- `502`: VNF operation failed
- `503`: Circuit breaker open (VNF instance unavailable)

#### Create NAT Rule

```http
POST /api/vnf/nat/create
Content-Type: application/json
Authorization: Bearer <token>

{
  "vnfInstanceId": "vnf-pfsense-001",
  "ruleId": "nat-rule-67890",
  "natType": "snat",
  "originalIp": "10.0.1.100",
  "translatedIp": "203.0.113.10",
  "protocol": "tcp",
  "enabled": true,
  "description": "SNAT for web server"
}
```

**NAT Types:**
- `snat`: Source NAT
- `dnat`: Destination NAT
- `1to1`: 1:1 NAT

**Response (201 Created):**
```json
{
  "success": true,
  "ruleId": "nat-rule-67890",
  "vnfInstanceId": "vnf-pfsense-001",
  "natType": "snat",
  "status": "created",
  "timestamp": "2025-11-07T18:30:00Z",
  "request_id": "e5f6g7h8"
}
```

---

## Client Libraries

### Python Client

```python
from vnf_broker_client import VNFBrokerClient

# Initialize with JWT token
client = VNFBrokerClient('https://10.1.3.177:8443', jwt_token='your-token')

# Or generate token from private key
client = VNFBrokerClient('https://10.1.3.177:8443', 
                         jwt_private_key_path='/path/to/private.pem')
client.generate_jwt_token()

# Check health
health = client.health()
print(f"Status: {health['status']}")

# Create firewall rule
result = client.create_firewall_rule(
    vnf_instance_id='vnf-pfsense-001',
    rule_id='fw-test-001',
    action='allow',
    protocol='tcp',
    source_ip='10.0.0.0/24',
    destination_ip='192.168.1.0/24',
    destination_port=443,
    description='Test HTTPS rule'
)
print(f"Created: {result['ruleId']}")
```

**Location:** `clients/python-manual/vnf_broker_client.py`

### Java Client (TODO)

Java client stubs can be generated using `openapi-generator-cli`:

```bash
cd openapi
python3 generate_client_stubs.py vnf-broker-api.yaml --lang java --output ../clients
```

---

## Dictionary Format

VNF vendor dictionaries are YAML files that define how to interact with each vendor's API.

**Schema:** `schemas/vnf-dictionary-schema.json`

**Example:** `dictionaries/pfsense-dictionary.yaml`

```yaml
version: "1.0"
vendor: "Netgate"
product: "pfSense"
firmware_version: "2.7+"

access:
  protocol: https
  port: 443
  basePath: /api/v1
  authType: token
  tokenRef: API_TOKEN
  tokenHeader: Authorization

services:
  Firewall:
    create:
      method: POST
      endpoint: /firewall/rule
      headers:
        Content-Type: application/json
      body: |
        {
          "interface": "wan",
          "type": "pass",
          "protocol": "${protocol}",
          "src": "${sourceCidr}",
          "dst": "any",
          "dstport": "${startPort}"
        }
      responseMapping:
        successCode: 201
        idPath: $.data.id
```

### Validate Dictionaries

```bash
# Validate single file
python3 dictionary_validator.py dictionaries/pfsense-dictionary.yaml

# Validate all dictionaries in directory
python3 dictionary_validator.py dictionaries/

# Development mode (allow unknown vendors)
python3 dictionary_validator.py --dev dictionaries/
```

---

## Features

### Idempotency

All create operations are idempotent using Redis-backed caching:

- **Key:** `idempotency:<operation>:<sha256_hash>`
- **TTL:** 24 hours (configurable)
- **Behavior:** Identical requests return cached response

**Example:**
```bash
# First request
curl -X POST https://localhost:8443/api/vnf/firewall/create \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"vnfInstanceId":"vnf-001", "ruleId":"fw-123", ...}'
# 201 Created

# Identical second request (within 24h)
curl -X POST https://localhost:8443/api/vnf/firewall/create \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"vnfInstanceId":"vnf-001", "ruleId":"fw-123", ...}'
# 200 OK (cached response)
```

### Rate Limiting

Per-client rate limiting using Redis sorted sets:

- **Default:** 100 requests per 60 seconds
- **Client ID:** JWT `sub` claim or IP address
- **Response:** HTTP 429 with `retry_after` header

**Configuration:**
```json
{
  "RATE_LIMIT_REQUESTS": 100,
  "RATE_LIMIT_WINDOW": 60
}
```

### Circuit Breaker

Protects against failing VNF backends:

- **Threshold:** 5 failures → circuit opens
- **Timeout:** 30 seconds before retry (half-open)
- **State:** Per VNF instance
- **Response:** HTTP 503 when circuit is open

**States:**
- `closed`: Normal operation
- `open`: Blocking requests after threshold failures
- `half_open`: Allowing single test request after timeout

**Check circuit breaker state:**
```bash
curl https://localhost:8443/metrics
```

### Request Validation

Pydantic models validate all requests:

- **Type checking:** Automatic type coercion and validation
- **Range validation:** Port numbers (1-65535), string lengths, etc.
- **Pattern matching:** IP addresses, CIDR notation
- **Enum validation:** Protocol types, actions, NAT types

**Validation error response:**
```json
{
  "error": "Validation error",
  "message": "Invalid request data",
  "details": [
    {
      "loc": ["destinationPort"],
      "msg": "ensure this value is less than or equal to 65535",
      "type": "value_error.number.not_le"
    }
  ]
}
```

---

## OpenAPI Specification

**Location:** `openapi/vnf-broker-api.yaml`

View interactive documentation:

1. **Swagger UI:**
   ```bash
   docker run -p 8080:8080 -e SWAGGER_JSON=/api/vnf-broker-api.yaml \
     -v $(pwd)/openapi:/api swaggerapi/swagger-ui
   ```
   
   Open: http://localhost:8080

2. **Redoc:**
   ```bash
   docker run -p 8080:80 -e SPEC_URL=/api/vnf-broker-api.yaml \
     -v $(pwd)/openapi:/api redocly/redoc
   ```

---

## Deployment

### Development

```bash
python3 vnf_broker_enhanced.py
```

### Production (Systemd)

```bash
# Copy service file
sudo cp vnf-broker.service /etc/systemd/system/

# Edit service file with correct paths
sudo nano /etc/systemd/system/vnf-broker.service

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable vnf-broker
sudo systemctl start vnf-broker

# Check status
sudo systemctl status vnf-broker
```

### Production (Docker)

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY vnf_broker_enhanced.py .
COPY keys/ keys/
COPY config.json /etc/vnf-broker/config.json

EXPOSE 8443

CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8443", \
     "--certfile=/etc/vnf-broker/server.crt", \
     "--keyfile=/etc/vnf-broker/server.key", \
     "vnf_broker_enhanced:app"]
```

---

## Troubleshooting

### Redis Connection Errors

```
ERROR: Failed to connect to Redis: Connection refused
```

**Solution:**
1. Start Redis: `sudo systemctl start redis`
2. Check Redis is listening: `redis-cli ping`
3. Update config: `REDIS_HOST`, `REDIS_PORT`

### JWT Validation Errors

```
ERROR: JWT public key not found: keys/jwt_public.pem
```

**Solution:**
1. Download public key from Build1
2. Place in `keys/jwt_public.pem`
3. Update config: `JWT_PUBLIC_KEY_PATH`

### Rate Limit Issues

**Symptoms:** HTTP 429 responses

**Check:**
```bash
# Check rate limit window
redis-cli KEYS "rate_limit:*"

# Clear rate limit for specific client
redis-cli DEL "rate_limit:cloudstack-management"
```

### Circuit Breaker Stuck Open

**Check state:**
```bash
curl https://localhost:8443/metrics
```

**Reset:** Restart broker (circuit breaker state is in-memory)

---

## Build2 Status

**Completed (2025-11-07):**
- [OK] Enhanced broker with hardening features
- [OK] Pydantic validation models
- [OK] Redis rate limiting
- [OK] Circuit breaker pattern
- [OK] RS256 JWT integration
- [OK] Dictionary validation framework
- [OK] OpenAPI specification
- [OK] Python client library
- [OK] Health and metrics endpoints

**Pending:**
- ⏳ Java client generation (requires openapi-generator)
- ⏳ Dictionary versioning system
- ⏳ Mock VNF server for testing

**Coordination:** msg_1762540639_7436

---

## Support

For issues or questions, contact Build2 (Copilot) via the messaging system.
