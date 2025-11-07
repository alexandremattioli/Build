#!/usr/bin/env python3
"""
VNF Broker API Client Stub Generator
=====================================
Generates Python and Java client libraries from OpenAPI spec.

Usage:
    python3 generate_client_stubs.py openapi/vnf-broker-api.yaml --lang python --output clients/python
    python3 generate_client_stubs.py openapi/vnf-broker-api.yaml --lang java --output clients/java

Requirements:
    pip install openapi-python-client
    # For Java: install openapi-generator-cli
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

def generate_python_client(spec_path: str, output_dir: str) -> bool:
    """Generate Python client using openapi-python-client"""
    try:
        cmd = [
            'openapi-python-client',
            'generate',
            '--path', spec_path,
            '--output-path', output_dir,
            '--meta', 'none'  # Skip metadata files
        ]
        
        print(f"Generating Python client...")
        print(f"Command: {' '.join(cmd)}")
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"✓ Python client generated: {output_dir}")
            return True
        else:
            print(f"✗ Python client generation failed:")
            print(result.stderr)
            return False
            
    except FileNotFoundError:
        print("✗ openapi-python-client not found. Install with:")
        print("  pip install openapi-python-client")
        return False

def generate_java_client(spec_path: str, output_dir: str, package_name: str = "org.apache.cloudstack.vnf.client") -> bool:
    """Generate Java client using openapi-generator"""
    try:
        # Check if openapi-generator is available
        check_cmd = ['openapi-generator-cli', 'version']
        subprocess.run(check_cmd, capture_output=True, check=True)
        
        cmd = [
            'openapi-generator-cli',
            'generate',
            '-i', spec_path,
            '-g', 'java',
            '-o', output_dir,
            '--package-name', package_name,
            '--artifact-id', 'vnf-broker-client',
            '--group-id', 'org.apache.cloudstack',
            '--artifact-version', '1.0.0',
            '--library', 'okhttp-gson'
        ]
        
        print(f"Generating Java client...")
        print(f"Command: {' '.join(cmd)}")
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"✓ Java client generated: {output_dir}")
            return True
        else:
            print(f"✗ Java client generation failed:")
            print(result.stderr)
            return False
            
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("✗ openapi-generator-cli not found. Install with:")
        print("  npm install -g @openapitools/openapi-generator-cli")
        print("  or download from: https://github.com/OpenAPITools/openapi-generator")
        return False

def generate_manual_python_client(output_dir: str) -> bool:
    """Generate a minimal Python client manually"""
    os.makedirs(output_dir, exist_ok=True)
    
    client_code = '''"""
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
'''
    
    with open(f"{output_dir}/vnf_broker_client.py", 'w') as f:
        f.write(client_code)
    
    print(f"✓ Manual Python client generated: {output_dir}/vnf_broker_client.py")
    return True

def main():
    parser = argparse.ArgumentParser(description='Generate VNF Broker API client stubs')
    parser.add_argument('spec', help='Path to OpenAPI spec (YAML or JSON)')
    parser.add_argument('--lang', choices=['python', 'java', 'both'], default='python',
                       help='Language for client generation')
    parser.add_argument('--output', default='clients',
                       help='Output directory base path')
    parser.add_argument('--package', default='org.apache.cloudstack.vnf.client',
                       help='Java package name')
    parser.add_argument('--manual', action='store_true',
                       help='Generate manual Python client (no dependencies)')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.spec):
        print(f"✗ OpenAPI spec not found: {args.spec}")
        sys.exit(1)
    
    success = True
    
    if args.manual or args.lang in ['python', 'both']:
        if args.manual:
            python_output = os.path.join(args.output, 'python-manual')
            success &= generate_manual_python_client(python_output)
        else:
            python_output = os.path.join(args.output, 'python')
            success &= generate_python_client(args.spec, python_output)
    
    if args.lang in ['java', 'both']:
        java_output = os.path.join(args.output, 'java')
        success &= generate_java_client(args.spec, java_output, args.package)
    
    if success:
        print("\n✓ Client generation complete")
        sys.exit(0)
    else:
        print("\n✗ Client generation failed")
        sys.exit(1)


if __name__ == '__main__':
    main()
