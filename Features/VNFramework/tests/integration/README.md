# Integration Tests for VNF Framework

End-to-end integration testing for CloudStack VNF Framework.

## Overview

These tests validate the complete integration flow:
1. **Broker-only tests**: Test broker functionality directly
2. **End-to-end tests**: Test complete CloudStack → Broker → VNF flow

## Test Suite

### Broker Tests
- `test_broker_health` - Verify broker health endpoint
- `test_broker_dictionaries` - Verify dictionary loading
- `test_create_firewall_rule_via_broker` - Direct broker rule creation
- `test_idempotency_via_broker` - Broker idempotency validation

### End-to-End Tests
- `test_create_firewall_rule_via_cloudstack` - CloudStack API → Broker → VNF
- `test_idempotency_via_cloudstack` - E2E idempotency validation
- `test_delete_firewall_rule_via_cloudstack` - Rule deletion flow

## Requirements

```bash
pip install requests python-dateutil
```

## Configuration

Set environment variables:

```bash
# CloudStack configuration
export CLOUDSTACK_URL="http://cloudstack-mgmt:8080/client/api"
export CLOUDSTACK_API_KEY="your-api-key"
export CLOUDSTACK_SECRET_KEY="your-secret-key"

# Broker configuration
export BROKER_URL="https://vr-ip:8443"
export BROKER_JWT_TOKEN="your-jwt-token"

# Test resources (for E2E tests)
export TEST_NETWORK_ID="network-uuid"
export TEST_VNF_INSTANCE_ID="vnf-instance-uuid"
```

## Running Tests

### All tests (broker + E2E):
```bash
python3 test_e2e_firewall.py
```

### Broker-only tests:
```bash
# Don't set TEST_NETWORK_ID and TEST_VNF_INSTANCE_ID
unset TEST_NETWORK_ID TEST_VNF_INSTANCE_ID
python3 test_e2e_firewall.py
```

## Example Output

```
============================================================
VNF Framework End-to-End Integration Tests
============================================================

Configuration:
  CloudStack URL: http://localhost:8080/client/api
  Broker URL: https://localhost:8443
  Test Network ID: (skip E2E tests)
  Test VNF Instance ID: (skip E2E tests)

▶ Running: Broker Health Check
  [OK] PASSED (0.12s)

▶ Running: Broker Dictionary Listing
  [OK] PASSED (0.08s)

▶ Running: Create Firewall Rule (Broker)
  [OK] PASSED (0.45s)

▶ Running: Idempotency Check (Broker)
  [OK] PASSED (0.62s)

⚠ Skipping E2E tests (TEST_NETWORK_ID/TEST_VNF_INSTANCE_ID not set)

▶ Cleanup: Removing test resources
  [OK] Cleaned up broker test rule

============================================================
TEST SUMMARY
============================================================
Total:  4
Passed: 4 [OK]
Failed: 0 ✗
Success Rate: 100.0%
============================================================
```

## Mock pfSense Server

For testing without a real pfSense appliance, you can use a mock server:

```python
# mock_pfsense_server.py
from flask import Flask, request, jsonify
import uuid

app = Flask(__name__)
rules = {}

@app.route('/api/v1/firewall/rules', methods=['POST'])
def create_rule():
    rule_id = str(uuid.uuid4())
    rules[rule_id] = request.json
    return jsonify({'id': rule_id, 'status': 'active'})

@app.route('/api/v1/firewall/rules/<rule_id>', methods=['GET'])
def get_rule(rule_id):
    if rule_id in rules:
        return jsonify(rules[rule_id])
    return jsonify({'error': 'Not found'}), 404

@app.route('/api/v1/firewall/rules/<rule_id>', methods=['DELETE'])
def delete_rule(rule_id):
    if rule_id in rules:
        del rules[rule_id]
        return jsonify({'success': True})
    return jsonify({'error': 'Not found'}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, ssl_context='adhoc')
```

Run mock server:
```bash
pip install flask pyopenssl
python3 mock_pfsense_server.py
```

Update pfSense dictionary to point to mock server:
```yaml
# dictionaries/pfsense_2.7.yaml
base_url: "https://localhost:8080/api/v1"
```

## Troubleshooting

### Broker connection failed
- Verify broker is running: `systemctl status vnfbroker`
- Check broker logs: `journalctl -u vnfbroker -f`
- Test health endpoint: `curl -k https://broker-ip:8443/health`

### CloudStack API errors
- Verify API credentials
- Check CloudStack management server logs: `/var/log/cloudstack/management/management-server.log`
- Ensure VNF Framework plugin is deployed

### Test failures
- Check test output for specific error messages
- Review broker logs for API call details
- Verify network connectivity between components

## CI/CD Integration

### GitLab CI Example:
```yaml
integration_tests:
  stage: test
  script:
    - pip install -r requirements.txt
    - export BROKER_URL="https://test-broker:8443"
    - export BROKER_JWT_TOKEN="${TEST_JWT_TOKEN}"
    - python3 tests/integration/test_e2e_firewall.py
  only:
    - feature/vnf-broker
```

### GitHub Actions Example:
```yaml
- name: Run Integration Tests
  env:
    BROKER_URL: https://test-broker:8443
    BROKER_JWT_TOKEN: ${{ secrets.TEST_JWT_TOKEN }}
  run: |
    pip install -r requirements.txt
    python3 tests/integration/test_e2e_firewall.py
```
