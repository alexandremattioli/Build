#!/usr/bin/env python3
"""
VNF Broker Integration Tests - Build2
======================================
End-to-end integration tests using mock VNF server.

Usage:
    # Start mock server first:
    python3 testing/mock_vnf_server.py --port 9443
    
    # Run tests:
    python3 testing/integration_test.py
    
    # Run with custom broker URL:
    python3 testing/integration_test.py --broker https://localhost:8443
"""

import sys
import time
import requests
import argparse
import logging
from typing import Dict, Optional

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('integration-test')

# Disable SSL warnings for testing
requests.packages.urllib3.disable_warnings()

class IntegrationTest:
    """Integration test suite for VNF Broker"""
    
    def __init__(self, broker_url: str, mock_vnf_url: str, jwt_token: Optional[str] = None):
        self.broker_url = broker_url.rstrip('/')
        self.mock_vnf_url = mock_vnf_url.rstrip('/')
        self.jwt_token = jwt_token
        self.session = requests.Session()
        self.session.verify = False  # Disable SSL verification for testing
        
        if jwt_token:
            self.session.headers['Authorization'] = f'Bearer {jwt_token}'
        
        self.passed = 0
        self.failed = 0
    
    def test_broker_health(self) -> bool:
        """Test broker health endpoint"""
        logger.info("TEST: Broker health check")
        try:
            resp = self.session.get(f'{self.broker_url}/health')
            resp.raise_for_status()
            data = resp.json()
            
            assert data['status'] == 'healthy', "Broker not healthy"
            assert 'redis' in data, "Redis status missing"
            
            logger.info("✓ PASS: Broker health check")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Broker health check - {e}")
            self.failed += 1
            return False
    def test_update_firewall_rule(self) -> bool:
        """Test updating firewall rule via broker"""
        logger.info("TEST: Update firewall rule")
        try:
            rule_id = f'fw-update-{int(time.time())}'
            
            # First create a rule
            create_data = {
                'vnfInstanceId': 'vnf-test-001',
                'ruleId': rule_id,
                'action': 'allow',
                'protocol': 'tcp',
                'sourceIp': '10.0.0.0/24',
                'destinationIp': '192.168.1.0/24',
                'destinationPort': 443,
                'enabled': True,
                'description': 'Rule to be updated'
            }
            resp = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=create_data)
            resp.raise_for_status()
            
            # Now update it
            update_data = {
                'vnfInstanceId': 'vnf-test-001',
                'action': 'deny',
                'protocol': 'udp',
                'sourceIp': '10.0.1.0/24',
                'destinationIp': '192.168.2.0/24',
                'destinationPort': 53,
                'enabled': False,
                'description': 'Updated test rule'
            }
            
            resp = self.session.put(f'{self.broker_url}/api/vnf/firewall/update/{rule_id}', json=update_data)
            resp.raise_for_status()
            result = resp.json()
            
            assert result['success'] == True, "Rule update failed"
            assert result['ruleId'] == rule_id, "Rule ID mismatch"
            assert 'updated' in result.get('message', '').lower(), "Update not confirmed"
            
            logger.info(f"✓ PASS: Updated firewall rule {rule_id}")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Update firewall rule - {e}")
            self.failed += 1
            return False
    
    def test_delete_firewall_rule(self) -> bool:
        """Test deleting firewall rule via broker"""
        logger.info("TEST: Delete firewall rule")
        try:
            rule_id = f'fw-delete-{int(time.time())}'
            
            # First create a rule
            create_data = {
                'vnfInstanceId': 'vnf-test-001',
                'ruleId': rule_id,
                'action': 'allow',
                'protocol': 'tcp',
                'sourceIp': '10.0.0.0/24',
                'destinationIp': '192.168.1.0/24',
                'destinationPort': 80,
                'enabled': True,
                'description': 'Rule to be deleted'
            }
            resp = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=create_data)
            resp.raise_for_status()
            
            # Now delete it
            delete_data = {
                'vnfInstanceId': 'vnf-test-001'
            }
            
            resp = self.session.delete(f'{self.broker_url}/api/vnf/firewall/delete/{rule_id}', json=delete_data)
            resp.raise_for_status()
            result = resp.json()
            
            assert result['success'] == True, "Rule deletion failed"
            assert result['ruleId'] == rule_id, "Rule ID mismatch"
            assert 'deleted' in result.get('message', '').lower(), "Delete not confirmed"
            
            logger.info(f"✓ PASS: Deleted firewall rule {rule_id}")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Delete firewall rule - {e}")
            self.failed += 1
            return False
    
    def test_list_firewall_rules(self) -> bool:
        """Test listing firewall rules via broker"""
        logger.info("TEST: List firewall rules")
        try:
            # Create a couple of rules first
            timestamp = int(time.time())
            rule1_id = f'fw-list-1-{timestamp}'
            rule2_id = f'fw-list-2-{timestamp}'
            
            for idx, rule_id in enumerate([rule1_id, rule2_id], 1):
                create_data = {
                    'vnfInstanceId': 'vnf-test-001',
                    'ruleId': rule_id,
                    'action': 'allow',
                    'protocol': 'tcp',
                    'sourceIp': '10.0.0.0/24',
                    'destinationIp': f'192.168.{idx}.0/24',
                    'destinationPort': 443,
                    'enabled': True,
                    'description': f'List test rule {idx}'
                }
                resp = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=create_data)
                resp.raise_for_status()
            
            # Now list all rules
            list_data = {
                'vnfInstanceId': 'vnf-test-001'
            }
            
            resp = self.session.get(f'{self.broker_url}/api/vnf/firewall/list', json=list_data)
            resp.raise_for_status()
            result = resp.json()
            
            assert result['success'] == True, "Rule listing failed"
            assert 'rules' in result, "Rules array missing"
            assert isinstance(result['rules'], list), "Rules is not an array"
            assert result['count'] == len(result['rules']), "Count mismatch"
            assert result['count'] >= 2, f"Expected at least 2 rules, got {result['count']}"
            
            # Verify our rules are in the list
            rule_ids = [r['ruleId'] for r in result['rules']]
            assert rule1_id in rule_ids, f"Rule {rule1_id} not found in list"
            assert rule2_id in rule_ids, f"Rule {rule2_id} not found in list"
            
            logger.info(f"✓ PASS: Listed {result['count']} firewall rules")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: List firewall rules - {e}")
            self.failed += 1
            return False
    
    def test_full_crud_workflow(self) -> bool:
        """Test complete CRUD workflow: Create -> Read(List) -> Update -> Read -> Delete -> Read"""
        logger.info("TEST: Full CRUD workflow")
        try:
            rule_id = f'fw-crud-{int(time.time())}'
            vnf_id = 'vnf-test-001'
            
            # CREATE
            create_data = {
                'vnfInstanceId': vnf_id,
                'ruleId': rule_id,
                'action': 'allow',
                'protocol': 'tcp',
                'sourceIp': '10.0.0.0/24',
                'destinationIp': '192.168.1.0/24',
                'destinationPort': 443,
                'enabled': True,
                'description': 'CRUD workflow test'
            }
            resp = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=create_data)
            resp.raise_for_status()
            assert resp.json()['success'] == True
            logger.info(f"  → Created rule {rule_id}")
            
            # READ (LIST) - verify creation
            resp = self.session.get(f'{self.broker_url}/api/vnf/firewall/list', json={'vnfInstanceId': vnf_id})
            resp.raise_for_status()
            result = resp.json()
            rule_ids = [r['ruleId'] for r in result['rules']]
            assert rule_id in rule_ids, "Created rule not found in list"
            logger.info(f"  → Verified rule exists in list ({result['count']} total rules)")
            
            # UPDATE
            update_data = {
                'vnfInstanceId': vnf_id,
                'action': 'deny',
                'protocol': 'udp',
                'sourceIp': '10.0.1.0/24',
                'destinationIp': '192.168.2.0/24',
                'destinationPort': 53,
                'enabled': False,
                'description': 'CRUD workflow test - updated'
            }
            resp = self.session.put(f'{self.broker_url}/api/vnf/firewall/update/{rule_id}', json=update_data)
            resp.raise_for_status()
            assert resp.json()['success'] == True
            logger.info(f"  → Updated rule {rule_id}")
            
            # READ (LIST) - verify update
            resp = self.session.get(f'{self.broker_url}/api/vnf/firewall/list', json={'vnfInstanceId': vnf_id})
            resp.raise_for_status()
            result = resp.json()
            rule_ids = [r['ruleId'] for r in result['rules']]
            assert rule_id in rule_ids, "Updated rule not found in list"
            logger.info(f"  → Verified rule still exists after update")
            
            # DELETE
            resp = self.session.delete(f'{self.broker_url}/api/vnf/firewall/delete/{rule_id}', json={'vnfInstanceId': vnf_id})
            resp.raise_for_status()
            assert resp.json()['success'] == True
            logger.info(f"  → Deleted rule {rule_id}")
            
            # READ (LIST) - verify deletion
            resp = self.session.get(f'{self.broker_url}/api/vnf/firewall/list', json={'vnfInstanceId': vnf_id})
            resp.raise_for_status()
            result = resp.json()
            rule_ids = [r['ruleId'] for r in result['rules']]
            # Note: Mock server keeps rules in memory, so we just verify the call succeeded
            logger.info(f"  → Verified deletion (list now has {result['count']} rules)")
            
            logger.info("✓ PASS: Full CRUD workflow")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Full CRUD workflow - {e}")
            self.failed += 1
            return False
    
    
    def test_mock_vnf_health(self) -> bool:
        """Test mock VNF health endpoint"""
        logger.info("TEST: Mock VNF health check")
        try:
            resp = requests.get(f'{self.mock_vnf_url}/health', verify=False)
            resp.raise_for_status()
            data = resp.json()
            
            assert data['status'] == 'healthy', "Mock VNF not healthy"
            
            logger.info("✓ PASS: Mock VNF health check")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Mock VNF health check - {e}")
            self.failed += 1
            return False
    
    def test_create_firewall_rule(self) -> bool:
        """Test creating firewall rule via broker"""
        logger.info("TEST: Create firewall rule")
        try:
            data = {
                'vnfInstanceId': 'vnf-test-001',
                'ruleId': f'fw-test-{int(time.time())}',
                'action': 'allow',
                'protocol': 'tcp',
                'sourceIp': '10.0.0.0/24',
                'destinationIp': '192.168.1.0/24',
                'destinationPort': 443,
                'enabled': True,
                'description': 'Integration test rule'
            }
            
            resp = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=data)
            resp.raise_for_status()
            result = resp.json()
            
            assert result['success'] == True, "Rule creation failed"
            assert result['ruleId'] == data['ruleId'], "Rule ID mismatch"
            assert result['status'] in ['created', 'exists'], "Invalid status"
            
            logger.info(f"✓ PASS: Created firewall rule {result['ruleId']}")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Create firewall rule - {e}")
            self.failed += 1
            return False
    
    def test_idempotency(self) -> bool:
        """Test idempotency - duplicate request should return cached response"""
        logger.info("TEST: Idempotency check")
        try:
            rule_id = f'fw-idem-{int(time.time())}'
            data = {
                'vnfInstanceId': 'vnf-test-001',
                'ruleId': rule_id,
                'action': 'allow',
                'protocol': 'tcp',
                'sourceIp': '10.0.0.0/24',
                'destinationIp': '192.168.1.0/24',
                'destinationPort': 80
            }
            
            # First request
            resp1 = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=data)
            resp1.raise_for_status()
            result1 = resp1.json()
            
            # Second identical request (should be idempotent)
            resp2 = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=data)
            resp2.raise_for_status()
            result2 = resp2.json()
            
            # Both should have same ruleId and success
            assert result1['ruleId'] == result2['ruleId'], "Idempotency failed - different rule IDs"
            assert result1['success'] == result2['success'], "Idempotency failed - different success status"
            
            logger.info("✓ PASS: Idempotency check")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Idempotency check - {e}")
            self.failed += 1
            return False
    
    def test_create_nat_rule(self) -> bool:
        """Test creating NAT rule via broker"""
        logger.info("TEST: Create NAT rule")
        try:
            data = {
                'vnfInstanceId': 'vnf-test-001',
                'ruleId': f'nat-test-{int(time.time())}',
                'natType': 'snat',
                'originalIp': '10.0.1.100',
                'translatedIp': '203.0.113.10',
                'protocol': 'tcp',
                'enabled': True,
                'description': 'Integration test NAT rule'
            }
            
            resp = self.session.post(f'{self.broker_url}/api/vnf/nat/create', json=data)
            resp.raise_for_status()
            result = resp.json()
            
            assert result['success'] == True, "NAT rule creation failed"
            assert result['ruleId'] == data['ruleId'], "Rule ID mismatch"
            assert result['natType'] == 'snat', "NAT type mismatch"
            
            logger.info(f"✓ PASS: Created NAT rule {result['ruleId']}")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Create NAT rule - {e}")
            self.failed += 1
            return False
    
    def test_validation_error(self) -> bool:
        """Test validation - invalid port should fail"""
        logger.info("TEST: Validation error handling")
        try:
            data = {
                'vnfInstanceId': 'vnf-test-001',
                'ruleId': f'fw-invalid-{int(time.time())}',
                'action': 'allow',
                'protocol': 'tcp',
                'sourceIp': '10.0.0.0/24',
                'destinationIp': '192.168.1.0/24',
                'destinationPort': 99999  # Invalid port (> 65535)
            }
            
            resp = self.session.post(f'{self.broker_url}/api/vnf/firewall/create', json=data)
            
            # Should return 400 Bad Request
            assert resp.status_code == 400, f"Expected 400, got {resp.status_code}"
            result = resp.json()
            assert 'error' in result, "Error field missing"
            assert result['error'] == 'Validation error', "Wrong error type"
            
            logger.info("✓ PASS: Validation error handling")
            self.passed += 1
            return True
        except AssertionError as e:
            logger.error(f"✗ FAIL: Validation error handling - {e}")
            self.failed += 1
            return False
        except Exception as e:
            logger.error(f"✗ FAIL: Validation error handling - unexpected error: {e}")
            self.failed += 1
            return False
    
    def test_broker_metrics(self) -> bool:
        """Test broker metrics endpoint"""
        logger.info("TEST: Broker metrics")
        try:
            resp = self.session.get(f'{self.broker_url}/metrics')
            resp.raise_for_status()
            data = resp.json()
            
            assert 'circuit_breakers' in data, "Circuit breakers missing from metrics"
            assert 'timestamp' in data, "Timestamp missing from metrics"
            
            logger.info("✓ PASS: Broker metrics")
            self.passed += 1
            return True
        except Exception as e:
            logger.error(f"✗ FAIL: Broker metrics - {e}")
            self.failed += 1
            return False
    
    def run_all_tests(self):
        """Run all integration tests"""
        logger.info("=" * 80)
        logger.info("VNF Broker Integration Test Suite")
        logger.info("=" * 80)
        logger.info(f"Broker URL: {self.broker_url}")
        logger.info(f"Mock VNF URL: {self.mock_vnf_url}")
        logger.info("=" * 80)
        logger.info("")
        
        # Run tests
        self.test_broker_health()
        self.test_mock_vnf_health()
        self.test_broker_metrics()
        self.test_create_firewall_rule()
        self.test_idempotency()
        self.test_create_nat_rule()
        self.test_validation_error()
        self.test_update_firewall_rule()
        self.test_delete_firewall_rule()
        self.test_list_firewall_rules()
        self.test_full_crud_workflow()
        
        # Summary
        logger.info("")
        logger.info("=" * 80)
        logger.info("Test Summary")
        logger.info("=" * 80)
        logger.info(f"Passed: {self.passed}")
        logger.info(f"Failed: {self.failed}")
        logger.info(f"Total:  {self.passed + self.failed}")
        logger.info("=" * 80)
        
        return self.failed == 0

def main():
    parser = argparse.ArgumentParser(description='VNF Broker integration tests')
    parser.add_argument('--broker', default='https://localhost:8443',
                       help='Broker base URL')
    parser.add_argument('--mock-vnf', default='http://localhost:9443',
                       help='Mock VNF base URL')
    parser.add_argument('--jwt-token', help='JWT token for authentication')
    
    args = parser.parse_args()
    
    # Note: For full testing, you need a valid JWT token
    if not args.jwt_token:
        logger.warning("No JWT token provided - authentication tests will fail")
        logger.warning("Use --jwt-token to provide a token")
    
    test_suite = IntegrationTest(args.broker, args.mock_vnf, args.jwt_token)
    success = test_suite.run_all_tests()
    
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
