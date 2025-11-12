#!/bin/bash
# VNF Framework Integration Test Runner
# Tests the complete VNF workflow from CloudStack → Broker → pfSense

set -e

# Configuration
VR_IP="${VR_IP:-192.168.1.100}"
BROKER_PORT="${BROKER_PORT:-8443}"
PFSENSE_IP="${PFSENSE_IP:-192.168.1.1}"
PFSENSE_API_KEY="${PFSENSE_API_KEY}"
REDIS_HOST="${REDIS_HOST:-${VR_IP}}"
REDIS_PORT="${REDIS_PORT:-6379}"
JWT_PRIVATE_KEY="${JWT_PRIVATE_KEY:-/tmp/vnf_broker_private.pem}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test result tracking
pass_test() {
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
    log_info "[OK] PASS: $1"
}

fail_test() {
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
    log_error "✗ FAIL: $1"
}

# Generate JWT token
generate_jwt() {
    local operation_id=$1
    local expiry=${2:-300}
    
    python3 << EOF
import jwt
import time
from datetime import datetime, timedelta

# Load private key
with open('${JWT_PRIVATE_KEY}', 'r') as f:
    private_key = f.read()

# Generate token
payload = {
    'sub': 'cloudstack-mgmt-server',
    'operation_id': '${operation_id}',
    'iat': int(time.time()),
    'exp': int(time.time()) + ${expiry}
}

token = jwt.encode(payload, private_key, algorithm='RS256')
print(token)
EOF
}

# Test 1: Broker Health Check
test_health_check() {
    log_info "Test 1: Broker Health Check"
    
    local response=$(curl -sk https://${VR_IP}:${BROKER_PORT}/health)
    
    if echo "$response" | grep -q '"status":"healthy"'; then
        pass_test "Broker is healthy"
    else
        fail_test "Broker health check failed: $response"
    fi
}

# Test 2: JWT Authentication
test_jwt_auth() {
    log_info "Test 2: JWT Authentication"
    
    local token=$(generate_jwt "test-auth-$(date +%s)")
    local response=$(curl -sk -H "Authorization: Bearer $token" \
        https://${VR_IP}:${BROKER_PORT}/health)
    
    if [ $? -eq 0 ]; then
        pass_test "JWT authentication successful"
    else
        fail_test "JWT authentication failed"
    fi
}

# Test 3: Invalid JWT Rejection
test_invalid_jwt() {
    log_info "Test 3: Invalid JWT Rejection"
    
    local response=$(curl -sk -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer invalid.jwt.token" \
        https://${VR_IP}:${BROKER_PORT}/health)
    
    if [ "$response" = "401" ]; then
        pass_test "Invalid JWT correctly rejected"
    else
        fail_test "Invalid JWT not rejected (got HTTP $response)"
    fi
}

# Test 4: Redis Connectivity
test_redis() {
    log_info "Test 4: Redis Connectivity"
    
    if command -v redis-cli &> /dev/null; then
        if redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} ping | grep -q "PONG"; then
            pass_test "Redis is accessible"
        else
            fail_test "Redis ping failed"
        fi
    else
        log_warn "redis-cli not available, skipping test"
    fi
}

# Test 5: Create Firewall Rule
test_create_firewall_rule() {
    log_info "Test 5: Create Firewall Rule"
    
    local token=$(generate_jwt "test-create-$(date +%s)")
    local request_data='{
        "rule_type": "pass",
        "interface": "wan",
        "protocol": "tcp",
        "source_cidr": "10.0.1.0/24",
        "source_port_start": "any",
        "destination_cidr": "192.168.1.100/32",
        "destination_port_start": "443",
        "destination_port_end": "443",
        "description": "Test HTTPS rule",
        "action": "allow"
    }'
    
    local response=$(curl -sk -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        https://${VR_IP}:${BROKER_PORT}/api/v1/firewall/rule)
    
    if echo "$response" | grep -q '"rule_id"'; then
        local rule_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin)['rule_id'])")
        pass_test "Firewall rule created: $rule_id"
        echo "$rule_id" > /tmp/test_rule_id.txt
    else
        fail_test "Firewall rule creation failed: $response"
    fi
}

# Test 6: Idempotency Check
test_idempotency() {
    log_info "Test 6: Idempotency Check"
    
    local token=$(generate_jwt "test-idempotency-$(date +%s)")
    local request_data='{
        "rule_type": "pass",
        "interface": "wan",
        "protocol": "tcp",
        "source_cidr": "10.0.2.0/24",
        "destination_cidr": "192.168.1.200/32",
        "destination_port_start": "80",
        "description": "Idempotency test rule"
    }'
    
    # First request
    local response1=$(curl -sk -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        https://${VR_IP}:${BROKER_PORT}/api/v1/firewall/rule)
    
    # Second identical request (should use cache)
    local response2=$(curl -sk -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        https://${VR_IP}:${BROKER_PORT}/api/v1/firewall/rule)
    
    if [ "$response1" = "$response2" ]; then
        pass_test "Idempotency working (identical responses)"
    else
        fail_test "Idempotency check failed (responses differ)"
    fi
}

# Test 7: List Firewall Rules
test_list_rules() {
    log_info "Test 7: List Firewall Rules"
    
    local token=$(generate_jwt "test-list-$(date +%s)")
    local response=$(curl -sk -H "Authorization: Bearer $token" \
        https://${VR_IP}:${BROKER_PORT}/api/v1/firewall/rules)
    
    if echo "$response" | grep -q '"rules"'; then
        pass_test "Firewall rules listed successfully"
    else
        fail_test "Firewall rules listing failed: $response"
    fi
}

# Test 8: Delete Firewall Rule
test_delete_rule() {
    log_info "Test 8: Delete Firewall Rule"
    
    if [ ! -f /tmp/test_rule_id.txt ]; then
        log_warn "No rule ID from create test, skipping delete test"
        return
    fi
    
    local rule_id=$(cat /tmp/test_rule_id.txt)
    local token=$(generate_jwt "test-delete-$(date +%s)")
    
    local response=$(curl -sk -X DELETE \
        -H "Authorization: Bearer $token" \
        -w "%{http_code}" -o /dev/null \
        https://${VR_IP}:${BROKER_PORT}/api/v1/firewall/rule/${rule_id})
    
    if [ "$response" = "200" ] || [ "$response" = "204" ]; then
        pass_test "Firewall rule deleted successfully"
        rm /tmp/test_rule_id.txt
    else
        fail_test "Firewall rule deletion failed (HTTP $response)"
    fi
}

# Test 9: Error Handling - Invalid Parameters
test_invalid_params() {
    log_info "Test 9: Error Handling - Invalid Parameters"
    
    local token=$(generate_jwt "test-invalid-$(date +%s)")
    local request_data='{
        "protocol": "tcp",
        "source_cidr": "invalid-cidr",
        "destination_port_start": "99999"
    }'
    
    local response=$(curl -sk -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$request_data" \
        -w "%{http_code}" -o /dev/null \
        https://${VR_IP}:${BROKER_PORT}/api/v1/firewall/rule)
    
    if [ "$response" = "400" ]; then
        pass_test "Invalid parameters correctly rejected (HTTP 400)"
    else
        fail_test "Invalid parameters not rejected (got HTTP $response)"
    fi
}

# Test 10: Performance - Response Time
test_response_time() {
    log_info "Test 10: Performance - Response Time"
    
    local token=$(generate_jwt "test-perf-$(date +%s)")
    local start=$(date +%s%N)
    
    curl -sk -H "Authorization: Bearer $token" \
        https://${VR_IP}:${BROKER_PORT}/health > /dev/null
    
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 )) # Convert to ms
    
    if [ $duration -lt 1000 ]; then
        pass_test "Response time acceptable: ${duration}ms"
    else
        fail_test "Response time too slow: ${duration}ms"
    fi
}

# Main test execution
main() {
    echo "========================================="
    echo "VNF Framework Integration Tests"
    echo "========================================="
    echo "VR IP: ${VR_IP}"
    echo "Broker Port: ${BROKER_PORT}"
    echo "Redis: ${REDIS_HOST}:${REDIS_PORT}"
    echo "========================================="
    echo ""
    
    # Prerequisites check
    if [ -z "$PFSENSE_API_KEY" ]; then
        log_warn "PFSENSE_API_KEY not set, some tests may fail"
    fi
    
    if [ ! -f "$JWT_PRIVATE_KEY" ]; then
        log_error "JWT private key not found: $JWT_PRIVATE_KEY"
        exit 1
    fi
    
    # Run tests
    test_health_check
    test_jwt_auth
    test_invalid_jwt
    test_redis
    test_create_firewall_rule
    test_idempotency
    test_list_rules
    test_delete_rule
    test_invalid_params
    test_response_time
    
    # Results summary
    echo ""
    echo "========================================="
    echo "Test Results Summary"
    echo "========================================="
    echo "Total Tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo "========================================="
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "All tests passed! [OK]"
        exit 0
    else
        log_error "Some tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"
