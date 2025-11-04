#!/usr/bin/env python3
"""
End-to-End Integration Test for VNF Framework Firewall Rules

Tests the complete flow:
CloudStack Management Server → VNF Broker → pfSense Appliance

Requirements:
- CloudStack Management Server with VNF Framework plugin deployed
- VNF Broker deployed to Virtual Router
- Mock pfSense API server (or real pfSense appliance)
- Test network and VNF instance configured
"""

import os
import sys
import time
import json
import requests
import hashlib
from typing import Dict, Optional
from dataclasses import dataclass

# Configuration from environment
CLOUDSTACK_URL = os.getenv('CLOUDSTACK_URL', 'http://localhost:8080/client/api')
CLOUDSTACK_API_KEY = os.getenv('CLOUDSTACK_API_KEY')
CLOUDSTACK_SECRET_KEY = os.getenv('CLOUDSTACK_SECRET_KEY')

BROKER_URL = os.getenv('BROKER_URL', 'https://localhost:8443')
BROKER_JWT_TOKEN = os.getenv('BROKER_JWT_TOKEN')

TEST_NETWORK_ID = os.getenv('TEST_NETWORK_ID')
TEST_VNF_INSTANCE_ID = os.getenv('TEST_VNF_INSTANCE_ID')


@dataclass
class TestResult:
    """Test result container"""
    name: str
    passed: bool
    duration: float
    error: Optional[str] = None
    details: Optional[Dict] = None


class CloudStackClient:
    """CloudStack API client"""
    
    def __init__(self, url: str, api_key: str, secret_key: str):
        self.url = url
        self.api_key = api_key
        self.secret_key = secret_key
    
    def _sign_request(self, params: Dict) -> str:
        """Sign API request with HMAC-SHA1"""
        import hmac
        import base64
        from urllib.parse import quote
        
        # Sort parameters
        sorted_params = sorted(params.items())
        query = '&'.join([f'{k}={quote(str(v), safe="")}' for k, v in sorted_params])
        
        # Create signature
        signature = hmac.new(
            self.secret_key.encode('utf-8'),
            query.lower().encode('utf-8'),
            hashlib.sha1
        ).digest()
        
        return base64.b64encode(signature).decode('utf-8')
    
    def request(self, command: str, params: Dict) -> Dict:
        """Make CloudStack API request"""
        request_params = {
            'command': command,
            'apiKey': self.api_key,
            'response': 'json',
            **params
        }
        
        signature = self._sign_request(request_params)
        request_params['signature'] = signature
        
        response = requests.get(self.url, params=request_params, verify=False)
        response.raise_for_status()
        
        return response.json()
    
    def create_vnf_firewall_rule(self, network_id: str, vnf_instance_id: str,
                                  rule_id: str, action: str, protocol: str,
                                  source_addr: str, dest_addr: str, dest_ports: str) -> Dict:
        """Create VNF firewall rule via CloudStack API"""
        params = {
            'networkid': network_id,
            'vnfinstanceid': vnf_instance_id,
            'ruleid': rule_id,
            'action': action,
            'protocol': protocol,
            'sourceaddress': source_addr,
            'destinationaddress': dest_addr,
            'destinationports': dest_ports
        }
        
        return self.request('createVnfFirewallRule', params)
    
    def delete_vnf_firewall_rule(self, vnf_instance_id: str, rule_id: str) -> Dict:
        """Delete VNF firewall rule via CloudStack API"""
        params = {
            'vnfinstanceid': vnf_instance_id,
            'ruleid': rule_id
        }
        
        return self.request('deleteVnfFirewallRule', params)
    
    def list_vnf_operations(self, vnf_instance_id: str) -> Dict:
        """List VNF operations (if API exists)"""
        params = {
            'vnfinstanceid': vnf_instance_id
        }
        
        try:
            return self.request('listVnfOperations', params)
        except Exception as e:
            return {'error': str(e), 'message': 'listVnfOperations not yet implemented'}


class BrokerClient:
    """VNF Broker API client"""
    
    def __init__(self, url: str, jwt_token: str):
        self.url = url
        self.jwt_token = jwt_token
        self.session = requests.Session()
        self.session.verify = False  # For self-signed certs
        self.session.headers.update({
            'Authorization': f'Bearer {jwt_token}',
            'Content-Type': 'application/json'
        })
    
    def health(self) -> Dict:
        """Check broker health"""
        response = self.session.get(f'{self.url}/health')
        response.raise_for_status()
        return response.json()
    
    def list_dictionaries(self) -> Dict:
        """List available vendor dictionaries"""
        response = self.session.get(f'{self.url}/dictionaries')
        response.raise_for_status()
        return response.json()
    
    def create_firewall_rule(self, rule_data: Dict, vendor: str = 'pfsense') -> Dict:
        """Create firewall rule via broker"""
        headers = {'X-VNF-Vendor': vendor}
        response = self.session.post(
            f'{self.url}/firewall/rules',
            json=rule_data,
            headers=headers
        )
        response.raise_for_status()
        return response.json()
    
    def get_firewall_rule(self, vendor_ref: str) -> Dict:
        """Get firewall rule by vendor reference"""
        response = self.session.get(f'{self.url}/firewall/rules/{vendor_ref}')
        response.raise_for_status()
        return response.json()
    
    def delete_firewall_rule(self, vendor_ref: str) -> Dict:
        """Delete firewall rule via broker"""
        response = self.session.delete(f'{self.url}/firewall/rules/{vendor_ref}')
        response.raise_for_status()
        return response.json()


class IntegrationTests:
    """Integration test suite"""
    
    def __init__(self):
        self.cs_client = CloudStackClient(CLOUDSTACK_URL, CLOUDSTACK_API_KEY, CLOUDSTACK_SECRET_KEY)
        self.broker_client = BrokerClient(BROKER_URL, BROKER_JWT_TOKEN)
        self.results = []
    
    def run_test(self, name: str, test_func):
        """Run a single test and record result"""
        print(f'\n▶ Running: {name}')
        start_time = time.time()
        
        try:
            details = test_func()
            duration = time.time() - start_time
            result = TestResult(name, True, duration, details=details)
            print(f'  ✓ PASSED ({duration:.2f}s)')
        except Exception as e:
            duration = time.time() - start_time
            result = TestResult(name, False, duration, error=str(e))
            print(f'  ✗ FAILED ({duration:.2f}s): {e}')
        
        self.results.append(result)
        return result
    
    def test_broker_health(self) -> Dict:
        """Test 1: Broker health endpoint"""
        health = self.broker_client.health()
        assert health.get('status') == 'healthy', 'Broker not healthy'
        assert 'redis' in health, 'Redis status missing'
        return health
    
    def test_broker_dictionaries(self) -> Dict:
        """Test 2: Broker dictionary listing"""
        dictionaries = self.broker_client.list_dictionaries()
        assert 'vendors' in dictionaries, 'Vendors list missing'
        assert 'pfsense' in dictionaries['vendors'], 'pfSense dictionary not loaded'
        return dictionaries
    
    def test_create_firewall_rule_via_broker(self) -> Dict:
        """Test 3: Create firewall rule via broker directly"""
        rule_data = {
            'ruleId': f'test-broker-{int(time.time())}',
            'action': 'allow',
            'protocol': 'tcp',
            'sourceAddress': '10.0.0.100/32',
            'destinationAddress': '10.0.0.200/32',
            'destinationPorts': ['443']
        }
        
        result = self.broker_client.create_firewall_rule(rule_data, vendor='pfsense')
        assert result.get('state') in ['active', 'pending'], f'Unexpected state: {result.get("state")}'
        assert 'vendorRef' in result, 'Vendor reference missing'
        
        # Store for cleanup
        self.test_vendor_ref = result['vendorRef']
        return result
    
    def test_idempotency_via_broker(self) -> Dict:
        """Test 4: Idempotency check via broker"""
        rule_data = {
            'ruleId': f'test-idempotent-{int(time.time())}',
            'action': 'allow',
            'protocol': 'tcp',
            'sourceAddress': '10.0.0.101/32',
            'destinationAddress': '10.0.0.201/32',
            'destinationPorts': ['80']
        }
        
        # First creation
        result1 = self.broker_client.create_firewall_rule(rule_data, vendor='pfsense')
        vendor_ref1 = result1['vendorRef']
        
        # Second creation (should be idempotent)
        result2 = self.broker_client.create_firewall_rule(rule_data, vendor='pfsense')
        vendor_ref2 = result2['vendorRef']
        
        # Should return same vendor reference
        assert vendor_ref1 == vendor_ref2, 'Idempotency failed: different vendor refs'
        
        return {'result1': result1, 'result2': result2, 'idempotent': True}
    
    def test_create_firewall_rule_via_cloudstack(self) -> Dict:
        """Test 5: Create firewall rule via CloudStack API (E2E)"""
        if not all([TEST_NETWORK_ID, TEST_VNF_INSTANCE_ID]):
            raise ValueError('TEST_NETWORK_ID and TEST_VNF_INSTANCE_ID must be set')
        
        rule_id = f'cs-test-{int(time.time())}'
        result = self.cs_client.create_vnf_firewall_rule(
            network_id=TEST_NETWORK_ID,
            vnf_instance_id=TEST_VNF_INSTANCE_ID,
            rule_id=rule_id,
            action='allow',
            protocol='tcp',
            source_addr='10.0.1.100/32',
            dest_addr='10.0.1.200/32',
            dest_ports='8080'
        )
        
        # Check response structure
        assert 'createvnffirewallruleresponse' in result, 'Invalid response structure'
        response = result['createvnffirewallruleresponse']
        assert response.get('state') in ['Completed', 'Pending'], f'Unexpected state: {response.get("state")}'
        
        # Store for cleanup
        self.test_cs_rule_id = rule_id
        return response
    
    def test_idempotency_via_cloudstack(self) -> Dict:
        """Test 6: Idempotency via CloudStack (E2E)"""
        if not all([TEST_NETWORK_ID, TEST_VNF_INSTANCE_ID]):
            raise ValueError('TEST_NETWORK_ID and TEST_VNF_INSTANCE_ID must be set')
        
        rule_id = f'cs-idempotent-{int(time.time())}'
        
        # First creation
        result1 = self.cs_client.create_vnf_firewall_rule(
            network_id=TEST_NETWORK_ID,
            vnf_instance_id=TEST_VNF_INSTANCE_ID,
            rule_id=rule_id,
            action='allow',
            protocol='tcp',
            source_addr='10.0.1.101/32',
            dest_addr='10.0.1.201/32',
            dest_ports='443'
        )
        
        # Second creation (should be idempotent)
        result2 = self.cs_client.create_vnf_firewall_rule(
            network_id=TEST_NETWORK_ID,
            vnf_instance_id=TEST_VNF_INSTANCE_ID,
            rule_id=rule_id,
            action='allow',
            protocol='tcp',
            source_addr='10.0.1.101/32',
            dest_addr='10.0.1.201/32',
            dest_ports='443'
        )
        
        # Both should succeed (idempotent)
        assert 'createvnffirewallruleresponse' in result1
        assert 'createvnffirewallruleresponse' in result2
        
        return {'result1': result1, 'result2': result2, 'idempotent': True}
    
    def test_delete_firewall_rule_via_cloudstack(self) -> Dict:
        """Test 7: Delete firewall rule via CloudStack (E2E)"""
        if not hasattr(self, 'test_cs_rule_id'):
            raise ValueError('No rule to delete (create test must run first)')
        
        result = self.cs_client.delete_vnf_firewall_rule(
            vnf_instance_id=TEST_VNF_INSTANCE_ID,
            rule_id=self.test_cs_rule_id
        )
        
        assert 'deletevnffirewallruleresponse' in result, 'Invalid response structure'
        return result['deletevnffirewallruleresponse']
    
    def cleanup(self):
        """Cleanup test resources"""
        print('\n▶ Cleanup: Removing test resources')
        
        # Cleanup broker test rule
        if hasattr(self, 'test_vendor_ref'):
            try:
                self.broker_client.delete_firewall_rule(self.test_vendor_ref)
                print('  ✓ Cleaned up broker test rule')
            except Exception as e:
                print(f'  ⚠ Failed to cleanup broker test rule: {e}')
    
    def print_summary(self):
        """Print test summary"""
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total - passed
        
        print('\n' + '='*60)
        print('TEST SUMMARY')
        print('='*60)
        print(f'Total:  {total}')
        print(f'Passed: {passed} ✓')
        print(f'Failed: {failed} ✗')
        print(f'Success Rate: {(passed/total*100):.1f}%')
        
        if failed > 0:
            print('\nFailed Tests:')
            for result in self.results:
                if not result.passed:
                    print(f'  ✗ {result.name}: {result.error}')
        
        print('='*60)
        
        return failed == 0


def main():
    """Main test runner"""
    print('='*60)
    print('VNF Framework End-to-End Integration Tests')
    print('='*60)
    
    # Validate configuration
    if not all([CLOUDSTACK_API_KEY, CLOUDSTACK_SECRET_KEY, BROKER_JWT_TOKEN]):
        print('ERROR: Missing required environment variables:')
        print('  - CLOUDSTACK_API_KEY')
        print('  - CLOUDSTACK_SECRET_KEY')
        print('  - BROKER_JWT_TOKEN')
        sys.exit(1)
    
    print(f'\nConfiguration:')
    print(f'  CloudStack URL: {CLOUDSTACK_URL}')
    print(f'  Broker URL: {BROKER_URL}')
    print(f'  Test Network ID: {TEST_NETWORK_ID or "(skip E2E tests)"}')
    print(f'  Test VNF Instance ID: {TEST_VNF_INSTANCE_ID or "(skip E2E tests)"}')
    
    # Run tests
    tests = IntegrationTests()
    
    try:
        # Broker-only tests
        tests.run_test('Broker Health Check', tests.test_broker_health)
        tests.run_test('Broker Dictionary Listing', tests.test_broker_dictionaries)
        tests.run_test('Create Firewall Rule (Broker)', tests.test_create_firewall_rule_via_broker)
        tests.run_test('Idempotency Check (Broker)', tests.test_idempotency_via_broker)
        
        # End-to-end tests (require CloudStack + VNF setup)
        if TEST_NETWORK_ID and TEST_VNF_INSTANCE_ID:
            tests.run_test('Create Firewall Rule (CloudStack E2E)', tests.test_create_firewall_rule_via_cloudstack)
            tests.run_test('Idempotency Check (CloudStack E2E)', tests.test_idempotency_via_cloudstack)
            tests.run_test('Delete Firewall Rule (CloudStack E2E)', tests.test_delete_firewall_rule_via_cloudstack)
        else:
            print('\n⚠ Skipping E2E tests (TEST_NETWORK_ID/TEST_VNF_INSTANCE_ID not set)')
        
    finally:
        tests.cleanup()
    
    # Print summary
    success = tests.print_summary()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
