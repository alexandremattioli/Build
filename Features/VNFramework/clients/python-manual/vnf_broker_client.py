"""
VNF Broker API Client - Build2
===============================
Minimal Python client for VNF Broker API.
"""

import requests
import jwt
import time
from typing import Dict, Any, Optional
from datetime import datetime, timedelta


class VNFBrokerClient:
    """Client for VNF Broker API"""
    
    def __init__(self, base_url: str, jwt_token: Optional[str] = None, 
                 jwt_private_key_path: Optional[str] = None):
        """
        Initialize client
        
        Args:
            base_url: Broker base URL (e.g., https://10.1.3.177:8443)
            jwt_token: Pre-generated JWT token
            jwt_private_key_path: Path to RS256 private key for generating tokens
        """
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.jwt_token = jwt_token
        self.jwt_private_key_path = jwt_private_key_path
        
        if jwt_token:
            self.session.headers['Authorization'] = f'Bearer {jwt_token}'
    
    def generate_jwt_token(self, subject: str = 'cloudstack-management', 
                          expires_in: int = 3600) -> str:
        """Generate JWT token using RS256 private key"""
        if not self.jwt_private_key_path:
            raise ValueError("jwt_private_key_path not configured")
        
        with open(self.jwt_private_key_path, 'r') as f:
            private_key = f.read()
        
        payload = {
            'sub': subject,
            'iat': int(time.time()),
            'exp': int(time.time()) + expires_in
        }
        
        token = jwt.encode(payload, private_key, algorithm='RS256')
        self.session.headers['Authorization'] = f'Bearer {token}'
        return token
    
    def health(self) -> Dict[str, Any]:
        """Check broker health"""
        resp = self.session.get(f'{self.base_url}/health', verify=False)
        resp.raise_for_status()
        return resp.json()
    
    def metrics(self) -> Dict[str, Any]:
        """Get broker metrics"""
        resp = self.session.get(f'{self.base_url}/metrics', verify=False)
        resp.raise_for_status()
        return resp.json()
    
    def create_firewall_rule(self, vnf_instance_id: str, rule_id: str,
                            action: str, protocol: str, source_ip: str,
                            destination_ip: str, destination_port: Optional[int] = None,
                            enabled: bool = True, description: Optional[str] = None) -> Dict[str, Any]:
        """Create firewall rule"""
        data = {
            'vnfInstanceId': vnf_instance_id,
            'ruleId': rule_id,
            'action': action,
            'protocol': protocol,
            'sourceIp': source_ip,
            'destinationIp': destination_ip,
            'enabled': enabled
        }
        
        if destination_port:
            data['destinationPort'] = destination_port
        if description:
            data['description'] = description
        
        resp = self.session.post(f'{self.base_url}/api/vnf/firewall/create', 
                                json=data, verify=False)
        resp.raise_for_status()
        return resp.json()
    
    def create_nat_rule(self, vnf_instance_id: str, rule_id: str,
                       nat_type: str, original_ip: str, translated_ip: str,
                       original_port: Optional[int] = None,
                       translated_port: Optional[int] = None,
                       protocol: str = 'any', enabled: bool = True,
                       description: Optional[str] = None) -> Dict[str, Any]:
        """Create NAT rule"""
        data = {
            'vnfInstanceId': vnf_instance_id,
            'ruleId': rule_id,
            'natType': nat_type,
            'originalIp': original_ip,
            'translatedIp': translated_ip,
            'protocol': protocol,
            'enabled': enabled
        }
        
        if original_port:
            data['originalPort'] = original_port
        if translated_port:
            data['translatedPort'] = translated_port
        if description:
            data['description'] = description
        
        resp = self.session.post(f'{self.base_url}/api/vnf/nat/create',
                                json=data, verify=False)
        resp.raise_for_status()
        return resp.json()
    
    def update_firewall_rule(self, rule_id: str, vnf_instance_id: str,
                            action: str, protocol: str, source_ip: str,
                            destination_ip: str, destination_port: Optional[int] = None,
                            enabled: bool = True, description: Optional[str] = None) -> Dict[str, Any]:
        """Update existing firewall rule"""
        data = {
            'vnfInstanceId': vnf_instance_id,
            'ruleId': rule_id,
            'action': action,
            'protocol': protocol,
            'sourceIp': source_ip,
            'destinationIp': destination_ip,
            'enabled': enabled
        }
        
        if destination_port:
            data['destinationPort'] = destination_port
        if description:
            data['description'] = description
        
        resp = self.session.put(f'{self.base_url}/api/vnf/firewall/update/{rule_id}',
                               json=data, verify=False)
        resp.raise_for_status()
        return resp.json()
    
    def delete_firewall_rule(self, rule_id: str, vnf_instance_id: str) -> Dict[str, Any]:
        """Delete firewall rule"""
        resp = self.session.delete(
            f'{self.base_url}/api/vnf/firewall/delete/{rule_id}',
            params={'vnfInstanceId': vnf_instance_id},
            verify=False
        )
        resp.raise_for_status()
        return resp.json()
    
    def list_firewall_rules(self, vnf_instance_id: str) -> Dict[str, Any]:
        """List all firewall rules for a VNF instance"""
        resp = self.session.get(
            f'{self.base_url}/api/vnf/firewall/list',
            params={'vnfInstanceId': vnf_instance_id},
            verify=False
        )
        resp.raise_for_status()
        return resp.json()


# Example usage
if __name__ == '__main__':
    # With pre-generated token
    client = VNFBrokerClient('https://localhost:8443', jwt_token='your-token-here')
    
    # Or generate token from private key
    # client = VNFBrokerClient('https://localhost:8443', 
    #                          jwt_private_key_path='/path/to/private.pem')
    # client.generate_jwt_token()
    
    # Check health
    health = client.health()
    print(f"Broker status: {health['status']}")
    
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
    print(f"Rule created: {result}")
    
    # List rules
    rules = client.list_firewall_rules('vnf-pfsense-001')
    print(f"Total rules: {rules['count']}")
    
    # Update rule
    update_result = client.update_firewall_rule(
        rule_id='fw-test-001',
        vnf_instance_id='vnf-pfsense-001',
        action='deny',
        protocol='tcp',
        source_ip='10.0.0.0/24',
        destination_ip='192.168.1.0/24',
        destination_port=22,
        description='Block SSH'
    )
    print(f"Rule updated: {update_result}")
    
    # Delete rule
    delete_result = client.delete_firewall_rule('fw-test-001', 'vnf-pfsense-001')
    print(f"Rule deleted: {delete_result}")

