#!/bin/bash
# VNF Broker Test Script
# Tests all broker endpoints with sample data

set -e

BROKER_URL="${BROKER_URL:-https://localhost:8443}"
JWT_TOKEN="${JWT_TOKEN:-}"
PRIVATE_KEY="${PRIVATE_KEY:-vnf_broker_private.pem}"

echo "=== VNF Broker Test Suite ==="
echo "Broker URL: $BROKER_URL"
echo ""

# Generate JWT token if not provided
if [ -z "$JWT_TOKEN" ]; then
    echo "Generating test JWT token..."
    if [ -f "$PRIVATE_KEY" ]; then
        # RS256 token generation (requires Python with PyJWT)
        JWT_TOKEN=$(python3 << PYEOF
import jwt
from datetime import datetime, timedelta

with open('$PRIVATE_KEY', 'r') as f:
    private_key = f.read()

payload = {
    'sub': 'test-user',
    'iat': datetime.utcnow(),
    'exp': datetime.utcnow() + timedelta(minutes=5),
    'scope': 'vnf:rw',
    'issuer': 'cloudstack'
}

token = jwt.encode(payload, private_key, algorithm='RS256')
print(token)
PYEOF
)
        echo "[OK] RS256 token generated"
    else
        # HS256 fallback
        JWT_SECRET="${JWT_SECRET:-changeme}"
        JWT_TOKEN=$(python3 << PYEOF
import jwt
from datetime import datetime, timedelta

payload = {
    'sub': 'test-user',
    'iat': datetime.utcnow(),
    'exp': datetime.utcnow() + timedelta(minutes=5),
    'scope': 'vnf:rw',
    'issuer': 'cloudstack'
}

token = jwt.encode(payload, '$JWT_SECRET', algorithm='HS256')
print(token)
PYEOF
)
        echo "[OK] HS256 token generated (using default secret)"
    fi
fi

echo "Token: ${JWT_TOKEN:0:50}..."
echo ""

# Test 1: Health Check
echo "Test 1: Health Check"
echo "-------------------"
RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" "$BROKER_URL/health")
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "Status: $HTTP_STATUS"
echo "Response: $BODY"

if [ "$HTTP_STATUS" = "200" ]; then
    echo "[OK] PASS"
else
    echo "✗ FAIL"
fi
echo ""

# Test 2: Create Firewall Rule
echo "Test 2: Create Firewall Rule"
echo "----------------------------"
IDEMPOTENCY_KEY="test-$(date +%s)-$$"

RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "$BROKER_URL/create-firewall-rule" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"idempotency_key\": \"$IDEMPOTENCY_KEY\",
        \"source\": {\"cidr\": \"10.0.0.0/24\"},
        \"destination\": {\"cidr\": \"192.168.1.0/24\"},
        \"service\": {\"protocol\": \"TCP\", \"ports\": [80, 443]},
        \"action\": \"ACCEPT\"
    }")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "Status: $HTTP_STATUS"
echo "Response: $BODY"

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
    RULE_ID=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('rule_id', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "Rule ID: $RULE_ID"
    echo "[OK] PASS"
else
    echo "✗ FAIL"
fi
echo ""

# Test 3: Idempotency - Repeat Same Request
echo "Test 3: Idempotency Test (Repeat Request)"
echo "-----------------------------------------"

RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "$BROKER_URL/create-firewall-rule" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"idempotency_key\": \"$IDEMPOTENCY_KEY\",
        \"source\": {\"cidr\": \"10.0.0.0/24\"},
        \"destination\": {\"cidr\": \"192.168.1.0/24\"},
        \"service\": {\"protocol\": \"TCP\", \"ports\": [80, 443]},
        \"action\": \"ACCEPT\"
    }")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "Status: $HTTP_STATUS"
echo "Response: $BODY"

if [ "$HTTP_STATUS" = "200" ]; then
    echo "[OK] PASS - Idempotency working (cached response returned)"
else
    echo "✗ FAIL - Expected 200 for duplicate request"
fi
echo ""

# Test 4: List Firewall Rules
echo "Test 4: List Firewall Rules"
echo "---------------------------"

RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "$BROKER_URL/list-firewall-rules" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "Status: $HTTP_STATUS"
echo "Response: $BODY"

if [ "$HTTP_STATUS" = "200" ]; then
    RULE_COUNT=$(echo "$BODY" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('rules', [])))" 2>/dev/null || echo "0")
    echo "Rules found: $RULE_COUNT"
    echo "[OK] PASS"
else
    echo "✗ FAIL"
fi
echo ""

# Test 5: Delete Firewall Rule
if [ ! -z "$RULE_ID" ] && [ "$RULE_ID" != "unknown" ]; then
    echo "Test 5: Delete Firewall Rule"
    echo "----------------------------"
    
    RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" \
        -X POST "$BROKER_URL/delete-firewall-rule" \
        -H "Authorization: Bearer $JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"idempotency_key\": \"delete-$IDEMPOTENCY_KEY\",
            \"rule_id\": \"$RULE_ID\"
        }")
    
    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')
    
    echo "Status: $HTTP_STATUS"
    echo "Response: $BODY"
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "[OK] PASS"
    else
        echo "✗ FAIL"
    fi
    echo ""
fi

# Test 6: Invalid JWT
echo "Test 6: Invalid JWT (Security Test)"
echo "-----------------------------------"

RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "$BROKER_URL/create-firewall-rule" \
    -H "Authorization: Bearer invalid.token.here" \
    -H "Content-Type: application/json" \
    -d '{"idempotency_key": "test", "source": {"cidr": "0.0.0.0/0"}}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)

echo "Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "401" ] || [ "$HTTP_STATUS" = "403" ]; then
    echo "[OK] PASS - Properly rejected invalid token"
else
    echo "✗ FAIL - Should reject invalid token"
fi
echo ""

# Summary
echo "=== Test Summary ==="
echo "All critical tests completed"
echo ""
echo "Manual verification steps:"
echo "  1. Check Redis keys: redis-cli KEYS 'idempotency:*'"
echo "  2. Check logs: journalctl -u vnfbroker -n 50"
echo "  3. Monitor Redis: redis-cli MONITOR"
