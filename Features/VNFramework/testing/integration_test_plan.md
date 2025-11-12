# VNF Framework Integration Test Plan

## Test Environment Setup

### Prerequisites
- CloudStack 4.21.0.0-SNAPSHOT with VNF plugin
- Virtual Router with VNF Broker deployed
- pfSense appliance accessible from VR
- Redis server running on VR
- Test network with firewall rules capability

### Components to Test
1. CloudStack Management Server → VNF Broker (JWT RS256)
2. VNF Broker → pfSense API (HTTPS + API key)
3. Redis idempotency layer
4. Dictionary parser and template rendering
5. End-to-end firewall rule lifecycle

---

## Test Scenarios

### Test 1: Health Check
**Objective:** Verify broker is running and accessible

**Steps:**
```bash
# From management server
curl -k https://<vr-ip>:8443/health

# Expected response:
{
  "status": "healthy",
  "timestamp": "2025-11-07T08:00:00Z",
  "redis": "connected",
  "version": "1.0.0"
}
```

**Success Criteria:**
- [OK] HTTP 200 status
- [OK] JSON response with "healthy" status
- [OK] Redis connection confirmed

---

### Test 2: JWT Authentication
**Objective:** Verify RS256 JWT token generation and validation

**Steps:**
```java
// CloudStack generates JWT
JwtTokenGenerator generator = new JwtTokenGenerator();
String token = generator.generateToken("vnf-operation-123", 300);

// Broker validates token
curl -k -H "Authorization: Bearer ${token}" \
  https://<vr-ip>:8443/health
```

**Success Criteria:**
- [OK] Token generated with RS256 algorithm
- [OK] Token contains operation ID claim
- [OK] Broker accepts valid token
- [OK] Broker rejects expired/invalid tokens (401)

---

### Test 3: Dictionary Loading
**Objective:** Verify pfSense dictionary can be loaded and parsed

**Steps:**
```bash
# Upload dictionary to VR
scp dictionaries/pfsense-test.yaml root@<vr-ip>:/etc/vnfbroker/dictionaries/

# Verify dictionary is valid
curl -k -H "Authorization: Bearer ${token}" \
  https://<vr-ip>:8443/dictionaries/pfsense
```

**Success Criteria:**
- [OK] Dictionary YAML parses without errors
- [OK] All required sections present (authentication, services, operations)
- [OK] Template variables identified correctly

---

### Test 4: Create Firewall Rule (First Request)
**Objective:** Test end-to-end firewall rule creation with idempotency

**CloudStack API Call:**
```bash
cloudmonkey create vnffirewallrule \
  vnfinstanceid=<vnf-id> \
  protocol=tcp \
  sourcecidr=10.0.1.0/24 \
  destinationcidr=192.168.1.100/32 \
  startport=443 \
  endport=443 \
  action=allow \
  description="Test HTTPS rule"
```

**Expected Flow:**
1. CloudStack → Generates JWT token
2. CloudStack → Calls VNF Broker with CreateFirewallRuleRequest
3. Broker → Checks Redis for idempotency key (miss)
4. Broker → Loads pfSense dictionary
5. Broker → Renders template with request parameters
6. Broker → Sends HTTPS POST to pfSense API
7. pfSense → Creates rule, returns rule ID
8. Broker → Stores response in Redis (24h TTL)
9. Broker → Returns response to CloudStack
10. CloudStack → Creates VnfOperationVO record

**Success Criteria:**
- [OK] HTTP 201 Created
- [OK] Response contains `ruleId` from pfSense
- [OK] Redis contains idempotency entry
- [OK] Firewall rule visible in pfSense UI
- [OK] VnfOperationVO created with status SUCCESS

---

### Test 5: Idempotency (Duplicate Request)
**Objective:** Verify idempotency prevents duplicate rule creation

**Steps:**
```bash
# Send exact same request again
cloudmonkey create vnffirewallrule \
  vnfinstanceid=<vnf-id> \
  protocol=tcp \
  sourcecidr=10.0.1.0/24 \
  destinationcidr=192.168.1.100/32 \
  startport=443 \
  endport=443 \
  action=allow \
  description="Test HTTPS rule"
```

**Expected Flow:**
1. CloudStack → Generates new JWT token (different timestamp)
2. CloudStack → Calls VNF Broker with same parameters
3. Broker → Checks Redis for idempotency key (HIT)
4. Broker → Returns cached response immediately
5. pfSense API is NOT called (no duplicate rule created)

**Success Criteria:**
- [OK] HTTP 200 OK (not 201)
- [OK] Response identical to first request
- [OK] Response time < 100ms (cache hit)
- [OK] Only ONE rule exists in pfSense
- [OK] Redis TTL refreshed to 24h

---

### Test 6: List Firewall Rules
**Objective:** Test rule listing and filtering

**Steps:**
```bash
cloudmonkey list vnffirewallrules \
  vnfinstanceid=<vnf-id> \
  protocol=tcp
```

**Expected Flow:**
1. CloudStack → Calls VNF Broker with ListFirewallRulesRequest
2. Broker → Loads dictionary, renders GET request
3. Broker → Calls pfSense API list endpoint
4. pfSense → Returns array of rules
5. Broker → Parses response using JSONPath from dictionary
6. Broker → Returns normalized rule list to CloudStack

**Success Criteria:**
- [OK] Returns array of firewall rules
- [OK] Each rule has: id, protocol, source, destination, ports, action
- [OK] Filtering by protocol works correctly
- [OK] Response format matches VnfFirewallRuleResponse schema

---

### Test 7: Delete Firewall Rule
**Objective:** Test rule deletion with idempotency

**Steps:**
```bash
cloudmonkey delete vnffirewallrule \
  id=<rule-id>
```

**Expected Flow:**
1. CloudStack → Calls VNF Broker with DeleteFirewallRuleRequest
2. Broker → Checks Redis for delete idempotency key
3. Broker → Renders DELETE request with rule ID
4. Broker → Calls pfSense DELETE endpoint
5. pfSense → Deletes rule, returns 204 No Content
6. Broker → Stores delete operation in Redis
7. CloudStack → Updates VnfOperationVO status

**Success Criteria:**
- [OK] HTTP 200 OK
- [OK] Rule deleted from pfSense
- [OK] Duplicate delete returns 200 (idempotent)
- [OK] VnfOperationVO status = SUCCESS

---

### Test 8: Error Handling - Invalid Parameters
**Objective:** Test validation and error responses

**Steps:**
```bash
# Invalid port range
cloudmonkey create vnffirewallrule \
  vnfinstanceid=<vnf-id> \
  protocol=tcp \
  sourcecidr=10.0.1.0/24 \
  destinationcidr=192.168.1.100/32 \
  startport=99999 \
  endport=443 \
  action=allow
```

**Success Criteria:**
- [OK] HTTP 400 Bad Request
- [OK] Error message indicates invalid port
- [OK] No rule created in pfSense
- [OK] VnfOperationVO status = FAILED with error details

---

### Test 9: Error Handling - pfSense Unreachable
**Objective:** Test broker behavior when pfSense is down

**Steps:**
```bash
# Stop pfSense or firewall it off
# Attempt rule creation
cloudmonkey create vnffirewallrule ...
```

**Expected Flow:**
1. Broker → Attempts connection to pfSense
2. Connection timeout after 10 seconds
3. Broker → Retries (up to 3 times)
4. Broker → Returns error after all retries exhausted

**Success Criteria:**
- [OK] HTTP 503 Service Unavailable
- [OK] Error message indicates connection failure
- [OK] VnfOperationVO status = FAILED
- [OK] Error code = VNF_COMMUNICATION_ERROR

---

### Test 10: Redis Failure Handling
**Objective:** Test broker behavior when Redis is unavailable

**Steps:**
```bash
# Stop Redis on VR
sudo systemctl stop redis-server

# Attempt rule creation
cloudmonkey create vnffirewallrule ...
```

**Expected Behavior:**
- Broker should fall back to non-idempotent mode
- Operations succeed but duplicates possible
- Warning logged about Redis unavailability

**Success Criteria:**
- [OK] Operation completes (no idempotency)
- [OK] Warning in broker logs
- [OK] Rule created successfully in pfSense

---

### Test 11: Template Rendering
**Objective:** Verify variable substitution in dictionary templates

**Test Data:**
```yaml
body:
  type: '${rule_type}'
  protocol: '${protocol}'
  src: '${source_cidr}'
  dst: '${destination_cidr}'
  dstport: '${destination_port_start}'
```

**Input:**
```json
{
  "rule_type": "pass",
  "protocol": "tcp",
  "source_cidr": "10.0.1.0/24",
  "destination_cidr": "192.168.1.100/32",
  "destination_port_start": "443"
}
```

**Expected Output:**
```json
{
  "type": "pass",
  "protocol": "tcp",
  "src": "10.0.1.0/24",
  "dst": "192.168.1.100/32",
  "dstport": "443"
}
```

**Success Criteria:**
- [OK] All ${variables} replaced correctly
- [OK] No remaining ${} placeholders in output
- [OK] Data types preserved (string, number, boolean)

---

### Test 12: Long-Running Operation
**Objective:** Test async operations and timeout handling

**Steps:**
```bash
# Create rule that takes >30 seconds to apply
cloudmonkey create vnffirewallrule ... (large ruleset)
```

**Success Criteria:**
- [OK] Request doesn't timeout prematurely
- [OK] CloudStack job status updated correctly
- [OK] Final status reflects actual pfSense state

---

## Performance Tests

### Test 13: Throughput Test
**Objective:** Measure max operations per second

**Steps:**
1. Create 100 firewall rules sequentially
2. Measure total time
3. Calculate ops/sec

**Target:** >10 operations/second

### Test 14: Concurrent Requests
**Objective:** Test broker under concurrent load

**Steps:**
1. Send 20 simultaneous create requests
2. Verify all succeed or fail gracefully

**Success Criteria:**
- [OK] All requests complete
- [OK] No race conditions
- [OK] Idempotency works correctly

---

## Security Tests

### Test 15: JWT Expiry
**Objective:** Verify expired tokens are rejected

**Steps:**
```bash
# Use token with exp=now-1hour
curl -k -H "Authorization: Bearer ${expired_token}" ...
```

**Success Criteria:**
- [OK] HTTP 401 Unauthorized
- [OK] Error indicates token expired

### Test 16: Invalid Signature
**Objective:** Verify token signature validation

**Steps:**
```bash
# Use token signed with wrong key
curl -k -H "Authorization: Bearer ${bad_token}" ...
```

**Success Criteria:**
- [OK] HTTP 401 Unauthorized
- [OK] Error indicates invalid signature

---

## Test Execution Checklist

- [ ] Test environment provisioned
- [ ] pfSense configured with API access
- [ ] VR broker deployed and running
- [ ] Redis running and accessible
- [ ] Dictionary uploaded to VR
- [ ] RS256 keypair generated and configured
- [ ] CloudStack VNF plugin compiled and deployed
- [ ] Management server restarted
- [ ] Test credentials obtained
- [ ] All 16 tests executed
- [ ] Results documented
- [ ] Issues logged for any failures
- [ ] Performance metrics recorded

---

## Test Results Template

```
Test ID: [1-16]
Test Name: [Name]
Date: YYYY-MM-DD
Tester: [Name]
Status: PASS/FAIL
Duration: [Xms]
Notes: [Any observations]
Issues: [Issue IDs if any]
```

---

## Rollback Procedure

If tests fail critically:

1. Stop VNF broker: `systemctl stop vnfbroker`
2. Disable VNF plugin in CloudStack
3. Restore database snapshot
4. Document failure details
5. Fix issues
6. Re-test from clean state

---

## Next Steps After Testing

1. Document any dictionary corrections needed
2. Update error codes based on real scenarios
3. Tune timeout values
4. Adjust Redis TTL if needed
5. Performance optimization
6. Security hardening
7. Production deployment planning
