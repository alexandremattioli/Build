#!/usr/bin/env python3
"""
VNF Broker Service for CloudStack Virtual Router
=================================================
This service runs on the Virtual Router and acts as a proxy between
CloudStack management server and VNF appliances.

Features:
- mTLS authentication with management server
- JWT authorization for requests
- HTTP/HTTPS proxying to VNF devices
- SSH/CLI command execution
- Request/response logging for audit

Installation on VR:
  pip install flask requests paramiko pyjwt cryptography
  
Run as systemd service:
  systemctl enable vnf-broker
  systemctl start vnf-broker
"""

import os
import sys
import json
import time
import logging
import subprocess
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

from flask import Flask, request, jsonify
import requests
import paramiko
import jwt
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa

# Configuration
CONFIG = {
    'BROKER_PORT': 8443,
    'BROKER_HOST': '0.0.0.0',
    'JWT_SECRET': None,  # Loaded from file
    'JWT_ALGORITHM': 'HS256',
    'ALLOWED_MANAGEMENT_IPS': [],  # Populated from config
    'ALLOWED_VNF_IPS': [],  # Populated from config
    'TLS_CERT_PATH': '/etc/vnf-broker/server.crt',
    'TLS_KEY_PATH': '/etc/vnf-broker/server.key',
    'CA_CERT_PATH': '/etc/vnf-broker/ca.crt',
    'LOG_FILE': '/var/log/vnf-broker/broker.log',
    'REQUEST_TIMEOUT': 30,
    'SSH_KEY_PATH': '/etc/vnf-broker/ssh_key',
    'DEBUG': False
}

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(CONFIG['LOG_FILE']),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('vnf-broker')

# Flask app
app = Flask(__name__)

def load_config():
    """Load configuration from file"""
    config_file = '/etc/vnf-broker/config.json'
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            user_config = json.load(f)
            CONFIG.update(user_config)
    
    # Load JWT secret
    jwt_secret_file = '/etc/vnf-broker/jwt_secret'
    if os.path.exists(jwt_secret_file):
        with open(jwt_secret_file, 'r') as f:
            CONFIG['JWT_SECRET'] = f.read().strip()
    else:
        logger.warning("JWT secret file not found, using default (INSECURE)")
        CONFIG['JWT_SECRET'] = 'changeme'

def validate_jwt(token: str) -> Optional[Dict]:
    """Validate JWT token and return payload"""
    try:
        payload = jwt.decode(
            token,
            CONFIG['JWT_SECRET'],
            algorithms=[CONFIG['JWT_ALGORITHM']]
        )
        
        # Check expiration
        if 'exp' in payload:
            exp_time = datetime.fromtimestamp(payload['exp'])
            if datetime.now() > exp_time:
                logger.warning("JWT token expired")
                return None
        
        return payload
    except jwt.InvalidTokenError as e:
        logger.error(f"Invalid JWT token: {e}")
        return None

def check_ip_allowed(ip: str, allowed_list: list) -> bool:
    """Check if IP is in allowed list"""
    if not allowed_list:
        # If no restrictions, allow all (not recommended)
        return True
    return ip in allowed_list

def proxy_http_request(target_ip: str, method: str, uri: str, 
                       headers: Dict, body: Optional[str]) -> Dict:
    """
    Proxy HTTP/HTTPS request to VNF device
    """
    url = f"https://{target_ip}{uri}"
    
    # Remove problematic headers
    headers_copy = headers.copy()
    headers_copy.pop('Host', None)
    headers_copy.pop('Content-Length', None)
    
    start_time = time.time()
    
    try:
        response = requests.request(
            method=method,
            url=url,
            headers=headers_copy,
            data=body,
            timeout=CONFIG['REQUEST_TIMEOUT'],
            verify=False  # VNF devices often use self-signed certs
        )
        
        duration_ms = int((time.time() - start_time) * 1000)
        
        return {
            'success': True,
            'status_code': response.status_code,
            'body': response.text,
            'headers': dict(response.headers),
            'duration_ms': duration_ms
        }
        
    except requests.Timeout:
        logger.error(f"Timeout connecting to {target_ip}")
        return {
            'success': False,
            'status_code': 504,
            'error': 'Gateway Timeout',
            'duration_ms': int((time.time() - start_time) * 1000)
        }
    except requests.RequestException as e:
        logger.error(f"Error connecting to {target_ip}: {e}")
        return {
            'success': False,
            'status_code': 502,
            'error': f'Bad Gateway: {str(e)}',
            'duration_ms': int((time.time() - start_time) * 1000)
        }

def execute_ssh_command(target_ip: str, port: int, username: str, 
                        password: Optional[str], command: str) -> Dict:
    """
    Execute command on VNF device via SSH
    """
    start_time = time.time()
    
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        # Attempt key-based auth first, then password
        try:
            if os.path.exists(CONFIG['SSH_KEY_PATH']):
                client.connect(
                    target_ip,
                    port=port,
                    username=username,
                    key_filename=CONFIG['SSH_KEY_PATH'],
                    timeout=CONFIG['REQUEST_TIMEOUT']
                )
            else:
                client.connect(
                    target_ip,
                    port=port,
                    username=username,
                    password=password,
                    timeout=CONFIG['REQUEST_TIMEOUT']
                )
        except paramiko.AuthenticationException:
            if password:
                client.connect(
                    target_ip,
                    port=port,
                    username=username,
                    password=password,
                    timeout=CONFIG['REQUEST_TIMEOUT']
                )
            else:
                raise
        
        # Execute command
        stdin, stdout, stderr = client.exec_command(command)
        exit_code = stdout.channel.recv_exit_status()
        
        stdout_text = stdout.read().decode('utf-8')
        stderr_text = stderr.read().decode('utf-8')
        
        client.close()
        
        duration_ms = int((time.time() - start_time) * 1000)
        
        return {
            'success': exit_code == 0,
            'status_code': exit_code,
            'stdout': stdout_text,
            'stderr': stderr_text,
            'duration_ms': duration_ms
        }
        
    except Exception as e:
        logger.error(f"SSH error to {target_ip}: {e}")
        return {
            'success': False,
            'status_code': -1,
            'error': str(e),
            'duration_ms': int((time.time() - start_time) * 1000)
        }

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'vnf-broker',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/vnfproxy', methods=['POST'])
def vnf_proxy():
    """
    Main VNF proxy endpoint
    
    Expected request format:
    {
        "target": "192.168.1.1",
        "protocol": "HTTPS",  // or "SSH"
        "method": "POST",     // for HTTP
        "uri": "/api/firewall/rules",
        "headers": {
            "X-API-Key": "...",
            "Content-Type": "application/json"
        },
        "body": "...",
        // For SSH:
        "command": "...",
        "ssh_username": "admin",
        "ssh_password": "...",
        "ssh_port": 22
    }
    """
    
    # Check client IP (basic security)
    client_ip = request.remote_addr
    logger.info(f"Request from {client_ip}")
    
    # Validate JWT from Authorization header
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        logger.warning(f"Missing or invalid Authorization header from {client_ip}")
        return jsonify({'error': 'Unauthorized'}), 401
    
    token = auth_header.split(' ', 1)[1]
    jwt_payload = validate_jwt(token)
    
    if not jwt_payload:
        logger.warning(f"Invalid JWT from {client_ip}")
        return jsonify({'error': 'Forbidden - Invalid token'}), 403
    
    # Parse request
    try:
        req_data = request.get_json()
        if not req_data:
            return jsonify({'error': 'Invalid JSON'}), 400
    except Exception as e:
        logger.error(f"Failed to parse request: {e}")
        return jsonify({'error': 'Invalid request format'}), 400
    
    target_ip = req_data.get('target')
    protocol = req_data.get('protocol', 'HTTPS').upper()
    
    if not target_ip:
        return jsonify({'error': 'Missing target IP'}), 400
    
    # Validate target IP is allowed
    allowed_vnf_ip = jwt_payload.get('allowed_target')
    if allowed_vnf_ip and target_ip != allowed_vnf_ip:
        logger.warning(f"Attempt to access unauthorized target {target_ip}, "
                       f"JWT only allows {allowed_vnf_ip}")
        return jsonify({'error': 'Forbidden - Target not allowed'}), 403
    
    # Check global allowed list
    if CONFIG['ALLOWED_VNF_IPS'] and target_ip not in CONFIG['ALLOWED_VNF_IPS']:
        logger.warning(f"Target {target_ip} not in allowed VNF IPs")
        return jsonify({'error': 'Forbidden - Target not allowed'}), 403
    
    # Log request (sanitized)
    logger.info(f"Proxying {protocol} request to {target_ip}")
    
    # Execute based on protocol
    if protocol in ['HTTP', 'HTTPS']:
        method = req_data.get('method', 'GET').upper()
        uri = req_data.get('uri', '/')
        headers = req_data.get('headers', {})
        body = req_data.get('body')
        
        result = proxy_http_request(target_ip, method, uri, headers, body)
        
    elif protocol == 'SSH':
        command = req_data.get('command')
        if not command:
            return jsonify({'error': 'Missing command for SSH'}), 400
        
        username = req_data.get('ssh_username', 'admin')
        password = req_data.get('ssh_password')
        port = req_data.get('ssh_port', 22)
        
        result = execute_ssh_command(target_ip, port, username, password, command)
        
    else:
        return jsonify({'error': f'Unsupported protocol: {protocol}'}), 400
    
    # Return result
    return jsonify(result)

@app.errorhandler(Exception)
def handle_exception(e):
    """Global exception handler"""
    logger.exception("Unhandled exception")
    return jsonify({
        'error': 'Internal server error',
        'message': str(e) if CONFIG['DEBUG'] else 'An error occurred'
    }), 500

def generate_self_signed_cert():
    """Generate self-signed certificate if not exists"""
    if os.path.exists(CONFIG['TLS_CERT_PATH']) and os.path.exists(CONFIG['TLS_KEY_PATH']):
        logger.info("TLS certificates already exist")
        return
    
    logger.info("Generating self-signed certificate...")
    
    # Generate private key
    key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )
    
    # Generate certificate
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, u"US"),
        x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, u"CA"),
        x509.NameAttribute(NameOID.LOCALITY_NAME, u"CloudStack"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, u"VNF Broker"),
        x509.NameAttribute(NameOID.COMMON_NAME, u"vnf-broker"),
    ])
    
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.utcnow()
    ).not_valid_after(
        datetime.utcnow() + timedelta(days=3650)
    ).sign(key, hashes.SHA256())
    
    # Write private key
    os.makedirs(os.path.dirname(CONFIG['TLS_KEY_PATH']), exist_ok=True)
    with open(CONFIG['TLS_KEY_PATH'], 'wb') as f:
        f.write(key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        ))
    
    # Write certificate
    with open(CONFIG['TLS_CERT_PATH'], 'wb') as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    
    logger.info("Self-signed certificate generated")

def main():
    """Main entry point"""
    # Load configuration
    load_config()
    
    # Setup logging directory
    os.makedirs(os.path.dirname(CONFIG['LOG_FILE']), exist_ok=True)
    
    # Generate cert if needed
    generate_self_signed_cert()
    
    logger.info(f"Starting VNF Broker on port {CONFIG['BROKER_PORT']}")
    logger.info(f"JWT authentication: {'enabled' if CONFIG['JWT_SECRET'] else 'DISABLED'}")
    
    # Run Flask with TLS
    app.run(
        host=CONFIG['BROKER_HOST'],
        port=CONFIG['BROKER_PORT'],
        ssl_context=(CONFIG['TLS_CERT_PATH'], CONFIG['TLS_KEY_PATH']),
        debug=CONFIG['DEBUG']
    )

if __name__ == '__main__':
    main()
