# VNF Broker CRUD Operations Guide

Complete guide to using all CRUD (Create, Read, Update, Delete) operations in the VNF Broker API.

## Table of Contents
- [Overview](#overview)
- [Authentication](#authentication)
- [Create Operations](#create-operations)
- [Read Operations](#read-operations)
- [Update Operations](#update-operations)
- [Delete Operations](#delete-operations)
- [Complete Workflows](#complete-workflows)
- [Error Handling](#error-handling)
- [Python Client Examples](#python-client-examples)

---

## Overview

The VNF Broker provides full RESTful CRUD operations for:
- **Firewall Rules**: Allow/deny rules with protocol/port/IP filtering
- **NAT Rules**: Source NAT (SNAT) and Destination NAT (DNAT) translation

All operations are:
- **Authenticated**: Require valid JWT token
- **Validated**: Pydantic schema enforcement
- **Idempotent**: Safe to retry (where applicable)
- **Rate-limited**: 100 req/min per client by default
- **Circuit-protected**: Automatic failure recovery

---

## Authentication

All API calls require a JWT token in the Authorization header:

```bash
# Generate token (example - use your secret key)
JWT_TOKEN=$(python3 -c "import jwt; print(jwt.encode({'user': 'admin'}, 'your-secret-key', algorithm='HS256'))")

# Use in requests
curl -H "Authorization: Bearer $JWT_TOKEN" https://localhost:8443/api/vnf/firewall/list
```

---

## Create Operations

### Create Firewall Rule

**Endpoint**: `POST /api/vnf/firewall/create`

**Request Body**:
```json
{
  "vnfInstanceId": "vnf-pfsense-001",
  "ruleId": "fw-allow-web-001",
  "action": "allow",
  "protocol": "tcp",
  "sourceIp": "10.0.0.0/24",
  "destinationIp": "192.168.1.100",
  "destinationPort": 443,
  "enabled": true,
  "description": "Allow HTTPS to web server"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "ruleId": "fw-allow-web-001",
  "vnfInstanceId": "vnf-pfsense-001",
  "status": "created",
  "message": "Firewall rule created successfully"
}
```

**cURL Example**:
```bash
curl -X POST https://localhost:8443/api/vnf/firewall/create \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnfInstanceId": "vnf-pfsense-001",
    "ruleId": "fw-allow-ssh-001",
    "action": "allow",
    "protocol": "tcp",
    "sourceIp": "10.0.1.0/24",
    "destinationIp": "192.168.1.50",
    "destinationPort": 22,
    "enabled": true,
    "description": "Allow SSH from admin network"
  }'
```

### Create NAT Rule

**Endpoint**: `POST /api/vnf/nat/create`

**Request Body**:
```json
{
  "vnfInstanceId": "vnf-pfsense-001",
  "ruleId": "nat-web-001",
  "natType": "dnat",
  "originalIp": "203.0.113.10",
  "translatedIp": "192.168.1.100",
  "protocol": "tcp",
  "originalPort": 80,
  "translatedPort": 8080,
  "enabled": true,
  "description": "Port forward to internal web server"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "ruleId": "nat-web-001",
  "vnfInstanceId": "vnf-pfsense-001",
  "natType": "dnat",
  "status": "created",
  "message": "NAT rule created successfully"
}
```

---

## Read Operations

### List All Firewall Rules

**Endpoint**: `GET /api/vnf/firewall/list`

**Request Body**:
```json
{
  "vnfInstanceId": "vnf-pfsense-001"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "count": 3,
  "rules": [
    {
      "ruleId": "fw-allow-web-001",
      "action": "allow",
      "protocol": "tcp",
      "sourceIp": "10.0.0.0/24",
      "destinationIp": "192.168.1.100",
      "destinationPort": 443,
      "enabled": true,
      "description": "Allow HTTPS to web server"
    },
    {
      "ruleId": "fw-allow-ssh-001",
      "action": "allow",
      "protocol": "tcp",
      "sourceIp": "10.0.1.0/24",
      "destinationIp": "192.168.1.50",
      "destinationPort": 22,
      "enabled": true,
      "description": "Allow SSH from admin network"
    },
    {
      "ruleId": "fw-deny-telnet-001",
      "action": "deny",
      "protocol": "tcp",
      "destinationPort": 23,
      "enabled": true,
      "description": "Block all Telnet"
    }
  ]
}
```

**cURL Example**:
```bash
curl -X GET https://localhost:8443/api/vnf/firewall/list \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vnfInstanceId": "vnf-pfsense-001"}'
```

---

## Update Operations

### Update Firewall Rule

**Endpoint**: `PUT /api/vnf/firewall/update/{ruleId}`

**Request Body**:
```json
{
  "vnfInstanceId": "vnf-pfsense-001",
  "action": "deny",
  "protocol": "tcp",
  "sourceIp": "10.0.2.0/24",
  "destinationIp": "192.168.1.100",
  "destinationPort": 443,
  "enabled": false,
  "description": "Updated: Deny HTTPS from untrusted network"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "ruleId": "fw-allow-web-001",
  "vnfInstanceId": "vnf-pfsense-001",
  "message": "Firewall rule updated successfully"
}
```

**cURL Example**:
```bash
curl -X PUT https://localhost:8443/api/vnf/firewall/update/fw-allow-web-001 \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnfInstanceId": "vnf-pfsense-001",
    "action": "deny",
    "protocol": "tcp",
    "sourceIp": "0.0.0.0/0",
    "destinationPort": 443,
    "enabled": true,
    "description": "Block all HTTPS (emergency rule)"
  }'
```

**Notes**:
- All fields except `vnfInstanceId` are optional
- Omitted fields retain their current values
- Rule is updated atomically on the VNF appliance

---

## Delete Operations

### Delete Firewall Rule

**Endpoint**: `DELETE /api/vnf/firewall/delete/{ruleId}`

**Request Body**:
```json
{
  "vnfInstanceId": "vnf-pfsense-001"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "ruleId": "fw-allow-web-001",
  "vnfInstanceId": "vnf-pfsense-001",
  "message": "Firewall rule deleted successfully"
}
```

**cURL Example**:
```bash
curl -X DELETE https://localhost:8443/api/vnf/firewall/delete/fw-allow-web-001 \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vnfInstanceId": "vnf-pfsense-001"}'
```

**Notes**:
- Deletion is idempotent (deleting non-existent rule returns success)
- Rule is immediately removed from VNF appliance
- No confirmation prompt (use with caution!)

---

## Complete Workflows

### Scenario 1: Add Web Server Access

```bash
# 1. Create firewall rule allowing HTTPS
curl -X POST https://localhost:8443/api/vnf/firewall/create \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnfInstanceId": "vnf-pfsense-001",
    "ruleId": "fw-web-https",
    "action": "allow",
    "protocol": "tcp",
    "sourceIp": "0.0.0.0/0",
    "destinationIp": "192.168.1.100",
    "destinationPort": 443,
    "enabled": true,
    "description": "Public HTTPS access to web server"
  }'

# 2. Create DNAT rule to forward public IP to internal server
curl -X POST https://localhost:8443/api/vnf/nat/create \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnfInstanceId": "vnf-pfsense-001",
    "ruleId": "nat-web-https",
    "natType": "dnat",
    "originalIp": "203.0.113.10",
    "translatedIp": "192.168.1.100",
    "protocol": "tcp",
    "originalPort": 443,
    "translatedPort": 443,
    "enabled": true,
    "description": "Forward public HTTPS to web server"
  }'

# 3. Verify both rules exist
curl -X GET https://localhost:8443/api/vnf/firewall/list \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vnfInstanceId": "vnf-pfsense-001"}'
```

### Scenario 2: Update Rule During Maintenance

```bash
# 1. Disable rule before maintenance
curl -X PUT https://localhost:8443/api/vnf/firewall/update/fw-web-https \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnfInstanceId": "vnf-pfsense-001",
    "enabled": false,
    "description": "Public HTTPS access to web server (DISABLED FOR MAINTENANCE)"
  }'

# 2. Perform maintenance...

# 3. Re-enable rule after maintenance
curl -X PUT https://localhost:8443/api/vnf/firewall/update/fw-web-https \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vnfInstanceId": "vnf-pfsense-001",
    "enabled": true,
    "description": "Public HTTPS access to web server"
  }'
```

### Scenario 3: Cleanup Old Rules

```bash
# 1. List all rules to find obsolete ones
curl -X GET https://localhost:8443/api/vnf/firewall/list \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vnfInstanceId": "vnf-pfsense-001"}' | jq '.rules[] | select(.description | contains("OLD"))'

# 2. Delete obsolete rules
for rule_id in fw-old-001 fw-old-002 fw-old-003; do
  curl -X DELETE https://localhost:8443/api/vnf/firewall/delete/$rule_id \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"vnfInstanceId": "vnf-pfsense-001"}'
done

# 3. Verify cleanup
curl -X GET https://localhost:8443/api/vnf/firewall/list \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vnfInstanceId": "vnf-pfsense-001"}'
```

---

## Error Handling

### Common Error Responses

#### 400 Bad Request - Validation Error
```json
{
  "error": "Validation error",
  "details": ["destinationPort must be between 1 and 65535"]
}
```

#### 401 Unauthorized - Invalid JWT
```json
{
  "error": "Unauthorized",
  "message": "Invalid or expired JWT token"
}
```

#### 404 Not Found - Rule Doesn't Exist (UPDATE only)
```json
{
  "error": "Not found",
  "message": "Firewall rule fw-nonexistent-001 not found"
}
```

#### 429 Too Many Requests - Rate Limit
```json
{
  "error": "Rate limit exceeded",
  "message": "Maximum 100 requests per minute"
}
```

#### 503 Service Unavailable - Circuit Breaker Open
```json
{
  "error": "Service unavailable",
  "message": "VNF instance vnf-pfsense-001 circuit breaker is OPEN"
}
```

### Error Handling Best Practices

```bash
# Use HTTP status codes to handle errors
response=$(curl -s -w "\n%{http_code}" -X POST https://localhost:8443/api/vnf/firewall/create \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vnfInstanceId": "vnf-pfsense-001", ...}')

status_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$status_code" -eq 200 ]; then
  echo "Success: $body"
elif [ "$status_code" -eq 400 ]; then
  echo "Validation error: $body"
elif [ "$status_code" -eq 429 ]; then
  echo "Rate limited, retrying in 60 seconds..."
  sleep 60
  # Retry logic here
elif [ "$status_code" -eq 503 ]; then
  echo "Circuit breaker open, backing off..."
  sleep 30
  # Retry logic here
else
  echo "Unexpected error ($status_code): $body"
fi
```

---

## Python Client Examples

### Using vnf_broker_client.py

```python
from vnf_broker_client import VNFBrokerClient

# Initialize client
client = VNFBrokerClient(
    base_url='https://localhost:8443',
    jwt_token='your-jwt-token-here',
    verify_ssl=False  # Only for testing
)

# Create firewall rule
result = client.create_firewall_rule(
    vnf_instance_id='vnf-pfsense-001',
    rule_id='fw-python-001',
    action='allow',
    protocol='tcp',
    source_ip='10.0.0.0/24',
    destination_ip='192.168.1.100',
    destination_port=443,
    enabled=True,
    description='Created via Python client'
)
print(f"Created: {result}")

# List all rules
rules = client.list_firewall_rules(vnf_instance_id='vnf-pfsense-001')
print(f"Total rules: {rules['count']}")
for rule in rules['rules']:
    print(f"  - {rule['ruleId']}: {rule['description']}")

# Update rule
result = client.update_firewall_rule(
    rule_id='fw-python-001',
    vnf_instance_id='vnf-pfsense-001',
    enabled=False,
    description='Disabled via Python client'
)
print(f"Updated: {result}")

# Delete rule
result = client.delete_firewall_rule(
    rule_id='fw-python-001',
    vnf_instance_id='vnf-pfsense-001'
)
print(f"Deleted: {result}")
```

### Complete CRUD Workflow

```python
#!/usr/bin/env python3
"""Complete CRUD workflow example"""
from vnf_broker_client import VNFBrokerClient
import time

def main():
    client = VNFBrokerClient(
        base_url='https://localhost:8443',
        jwt_token='your-token-here',
        verify_ssl=False
    )
    
    vnf_id = 'vnf-pfsense-001'
    rule_id = f'fw-workflow-{int(time.time())}'
    
    print("=== CREATE ===")
    result = client.create_firewall_rule(
        vnf_instance_id=vnf_id,
        rule_id=rule_id,
        action='allow',
        protocol='tcp',
        source_ip='10.0.0.0/24',
        destination_ip='192.168.1.100',
        destination_port=443,
        enabled=True,
        description='CRUD workflow test'
    )
    print(f"Created: {result['ruleId']}")
    
    print("\n=== READ (LIST) ===")
    rules = client.list_firewall_rules(vnf_instance_id=vnf_id)
    print(f"Found {rules['count']} rules")
    assert rule_id in [r['ruleId'] for r in rules['rules']]
    
    print("\n=== UPDATE ===")
    result = client.update_firewall_rule(
        rule_id=rule_id,
        vnf_instance_id=vnf_id,
        action='deny',
        enabled=False,
        description='CRUD workflow test - UPDATED'
    )
    print(f"Updated: {result['ruleId']}")
    
    print("\n=== READ (LIST) - verify update ===")
    rules = client.list_firewall_rules(vnf_instance_id=vnf_id)
    assert rule_id in [r['ruleId'] for r in rules['rules']]
    
    print("\n=== DELETE ===")
    result = client.delete_firewall_rule(
        rule_id=rule_id,
        vnf_instance_id=vnf_id
    )
    print(f"Deleted: {result['ruleId']}")
    
    print("\n[OK] Complete CRUD workflow successful!")

if __name__ == '__main__':
    main()
```

---

## See Also

- [README.md](README.md) - Project overview
- [QUICKSTART.md](QUICKSTART.md) - Getting started guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [vnf-broker-api.yaml](vnf-broker-api.yaml) - OpenAPI specification
- [PROMETHEUS.md](PROMETHEUS.md) - Metrics and monitoring
