#!/usr/bin/env python3
"""
VNF Broker Service with Redis Idempotency - Build2 Implementation
==================================================================
Enhanced version with Redis-backed idempotency cache per Build1 requirements.

Key improvements over in-memory version:
- Redis connection pooling for production reliability
- 24h TTL for idempotency keys (configurable)
- Persistent cache across broker restarts
- Cluster-safe for multi-broker deployments

Installation:
  pip install flask requests redis pyjwt cryptography

Configuration:
  /etc/vnf-broker/config.json:
  {
    "REDIS_HOST": "localhost",
    "REDIS_PORT": 6379,
    "REDIS_DB": 0,
    "REDIS_PASSWORD": null,
    "IDEMPOTENCY_TTL_SECONDS": 86400,
    "JWT_ALGORITHM": "RS256",
    "JWT_PUBLIC_KEY_PATH": "/etc/vnf-broker/jwt_public.pem"
  }
"""

import os
import sys
import json
import time
import logging
import hashlib
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

from flask import Flask, request, jsonify
import requests
import redis
from redis.connection import ConnectionPool
import jwt
from cryptography.hazmat.primitives import serialization

# Configuration defaults
CONFIG = {
    'BROKER_PORT': 8443,
    'BROKER_HOST': '0.0.0.0',
    'JWT_PUBLIC_KEY_PATH': '/etc/vnf-broker/jwt_public.pem',
    'JWT_ALGORITHM': 'RS256',  # RS256 per Build1 requirement
    'REDIS_HOST': 'localhost',
    'REDIS_PORT': 6379,
    'REDIS_DB': 0,
    'REDIS_PASSWORD': None,
    'REDIS_MAX_CONNECTIONS': 10,
    'IDEMPOTENCY_TTL_SECONDS': 86400,  # 24 hours
    'ALLOWED_MANAGEMENT_IPS': [],
    'ALLOWED_VNF_IPS': [],
    'TLS_CERT_PATH': '/etc/vnf-broker/server.crt',
    'TLS_KEY_PATH': '/etc/vnf-broker/server.key',
    'LOG_FILE': '/var/log/vnf-broker/broker.log',
    'REQUEST_TIMEOUT': 30,
    'DEBUG': False
}

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(CONFIG.get('LOG_FILE', '/var/log/vnf-broker/broker.log')),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('vnf-broker')

# Flask app
app = Flask(__name__)

# Redis connection pool (initialized in main())
redis_pool: Optional[ConnectionPool] = None
redis_client: Optional[redis.Redis] = None

def load_config():
    """Load configuration from file"""
    config_file = '/etc/vnf-broker/config.json'
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            user_config = json.load(f)
            CONFIG.update(user_config)
        logger.info(f"Loaded configuration from {config_file}")
    else:
        logger.warning(f"Config file {config_file} not found, using defaults")

def init_redis():
    """Initialize Redis connection pool"""
    global redis_pool, redis_client
    
    try:
        redis_pool = ConnectionPool(
            host=CONFIG['REDIS_HOST'],
            port=CONFIG['REDIS_PORT'],
            db=CONFIG['REDIS_DB'],
            password=CONFIG['REDIS_PASSWORD'],
            max_connections=CONFIG['REDIS_MAX_CONNECTIONS'],
            decode_responses=True,  # Auto-decode bytes to str
            socket_connect_timeout=5,
            socket_keepalive=True
        )
        
        redis_client = redis.Redis(connection_pool=redis_pool)
        
        # Test connection
        redis_client.ping()
        logger.info(f"Redis connection established: {CONFIG['REDIS_HOST']}:{CONFIG['REDIS_PORT']}")
        
    except redis.ConnectionError as e:
        logger.error(f"Failed to connect to Redis: {e}")
        logger.error("Broker will not start without Redis - per Build1 requirements")
        sys.exit(1)

def load_jwt_public_key():
    """Load RSA public key for JWT verification"""
    key_path = CONFIG['JWT_PUBLIC_KEY_PATH']
    
    if not os.path.exists(key_path):
        logger.error(f"JWT public key not found at {key_path}")
        logger.error("Broker requires RS256 JWT verification per Build1 spec")
        sys.exit(1)
    
    with open(key_path, 'rb') as f:
        public_key = serialization.load_pem_public_key(f.read())
    
    logger.info(f"Loaded RS256 public key from {key_path}")
    return public_key

# Load JWT public key at module level
JWT_PUBLIC_KEY = None

def validate_jwt(token: str) -> Optional[Dict]:
    """
    Validate JWT token with RS256 algorithm
    Per Build1 requirements: RS256 with public key verification
    """
    try:
        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=[CONFIG['JWT_ALGORITHM']]
        )
        
        # Check expiration (jwt.decode already checks this, but explicit check for logging)
        if 'exp' in payload:
            exp_time = datetime.fromtimestamp(payload['exp'])
            if datetime.now() > exp_time:
                logger.warning("JWT token expired")
                return None
        
        logger.debug(f"JWT validated successfully for subject: {payload.get('sub', 'unknown')}")
        return payload
        
    except jwt.ExpiredSignatureError:
        logger.warning("JWT token expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.error(f"Invalid JWT token: {e}")
        return None

def compute_idempotency_key(operation: str, params: Dict) -> str:
    """
    Compute idempotency key for request
    Format: idempotency:<operation>:<sha256_hash_of_params>
    """
    # Sort params for consistent hashing
    params_str = json.dumps(params, sort_keys=True)
    params_hash = hashlib.sha256(params_str.encode()).hexdigest()[:16]
    
    return f"idempotency:{operation}:{params_hash}"

def check_idempotency(operation: str, params: Dict) -> Optional[Dict]:
    """
    Check if this operation was already executed (idempotency check)
    Returns cached response if found, None otherwise
    """
    key = compute_idempotency_key(operation, params)
    
    try:
        cached_response = redis_client.get(key)
        if cached_response:
            logger.info(f"Idempotency cache HIT for key: {key}")
            return json.loads(cached_response)
        else:
            logger.debug(f"Idempotency cache MISS for key: {key}")
            return None
    except redis.RedisError as e:
        logger.error(f"Redis error during idempotency check: {e}")
        # Fail open - continue processing rather than return error
        return None

def store_idempotency(operation: str, params: Dict, response: Dict):
    """
    Store operation response for idempotency with 24h TTL
    """
    key = compute_idempotency_key(operation, params)
    ttl = CONFIG['IDEMPOTENCY_TTL_SECONDS']
    
    try:
        response_json = json.dumps(response)
        redis_client.setex(key, ttl, response_json)
        logger.info(f"Stored idempotency cache for key: {key} (TTL: {ttl}s)")
    except redis.RedisError as e:
        logger.error(f"Redis error storing idempotency: {e}")
        # Non-fatal - continue without caching

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

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint with Redis status"""
    redis_status = 'unknown'
    try:
        redis_client.ping()
        redis_status = 'connected'
    except Exception as e:
        redis_status = f'error: {str(e)}'
    
    return jsonify({
        'status': 'healthy',
        'service': 'vnf-broker',
        'redis': redis_status,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/vnf/firewall/create', methods=['POST'])
def create_firewall_rule():
    """
    Create VNF firewall rule with idempotency support
    
    Request format:
    {
        "vnfInstanceId": "uuid",
        "ruleId": "unique_rule_id",
        "action": "allow|deny",
        "protocol": "tcp|udp|icmp|any",
        "sourceIp": "10.0.0.0/24",
        "destinationIp": "192.168.1.0/24",
        "destinationPort": 443,
        "enabled": true,
        "description": "Web traffic rule"
    }
    """
    # Validate JWT
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({'error': 'Unauthorized'}), 401
    
    token = auth_header.split(' ', 1)[1]
    jwt_payload = validate_jwt(token)
    
    if not jwt_payload:
        return jsonify({'error': 'Forbidden - Invalid token'}), 403
    
    # Parse request
    try:
        req_data = request.get_json()
        if not req_data:
            return jsonify({'error': 'Invalid JSON'}), 400
    except Exception as e:
        logger.error(f"Failed to parse request: {e}")
        return jsonify({'error': 'Invalid request format'}), 400
    
    # Extract parameters
    rule_id = req_data.get('ruleId')
    vnf_instance_id = req_data.get('vnfInstanceId')
    
    if not rule_id or not vnf_instance_id:
        return jsonify({'error': 'Missing required fields: ruleId, vnfInstanceId'}), 400
    
    operation = 'firewall.create'
    params = {
        'ruleId': rule_id,
        'vnfInstanceId': vnf_instance_id,
        'action': req_data.get('action'),
        'protocol': req_data.get('protocol'),
        'sourceIp': req_data.get('sourceIp'),
        'destinationIp': req_data.get('destinationIp'),
        'destinationPort': req_data.get('destinationPort')
    }
    
    # Check idempotency FIRST
    cached_response = check_idempotency(operation, params)
    if cached_response:
        logger.info(f"Returning cached response for rule {rule_id}")
        return jsonify(cached_response), 200
    
    # Execute actual VNF operation (placeholder - would call proxy_http_request)
    # For now, simulate success
    response_data = {
        'success': True,
        'ruleId': rule_id,
        'vnfInstanceId': vnf_instance_id,
        'status': 'created',
        'timestamp': datetime.now().isoformat()
    }
    
    # Store for idempotency
    store_idempotency(operation, params, response_data)
    
    return jsonify(response_data), 201

@app.errorhandler(Exception)
def handle_exception(e):
    """Global exception handler"""
    logger.exception("Unhandled exception")
    return jsonify({
        'error': 'Internal server error',
        'message': str(e) if CONFIG['DEBUG'] else 'An error occurred'
    }), 500

def main():
    """Main entry point"""
    global JWT_PUBLIC_KEY
    
    # Load configuration
    load_config()
    
    # Setup logging directory
    os.makedirs(os.path.dirname(CONFIG['LOG_FILE']), exist_ok=True)
    
    # Initialize Redis connection pool
    init_redis()
    
    # Load JWT public key for RS256
    JWT_PUBLIC_KEY = load_jwt_public_key()
    
    logger.info(f"Starting VNF Broker with Redis idempotency on port {CONFIG['BROKER_PORT']}")
    logger.info(f"JWT Algorithm: {CONFIG['JWT_ALGORITHM']} (RS256)")
    logger.info(f"Redis: {CONFIG['REDIS_HOST']}:{CONFIG['REDIS_PORT']}")
    logger.info(f"Idempotency TTL: {CONFIG['IDEMPOTENCY_TTL_SECONDS']}s (24h)")
    
    # Run Flask (production deployment should use gunicorn/uwsgi)
    app.run(
        host=CONFIG['BROKER_HOST'],
        port=CONFIG['BROKER_PORT'],
        debug=CONFIG['DEBUG']
    )

if __name__ == '__main__':
    main()
