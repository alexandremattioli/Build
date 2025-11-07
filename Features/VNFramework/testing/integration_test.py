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
