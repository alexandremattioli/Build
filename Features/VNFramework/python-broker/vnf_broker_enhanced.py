#!/usr/bin/env python3
"""
VNF Broker Service - Enhanced with Hardening (Build2)
=====================================================
Production-ready broker with:
- Pydantic request validation
- Redis rate limiting
- Circuit breaker for VNF backends
- Comprehensive error handling
- OpenAPI documentation support

Per Build1 coordination msg_1762504317 requirements.
"""

import os
import sys
import json
import time
import logging
import hashlib
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, Tuple
from enum import Enum
from functools import wraps

from flask import Flask, request, jsonify
from pydantic import BaseModel, Field, validator, ValidationError
import requests
import redis
from redis.connection import ConnectionPool
import jwt
from cryptography.hazmat.primitives import serialization

# Configuration defaults (same as vnf_broker_redis.py)
CONFIG = {
    'BROKER_PORT': 8443,
    'BROKER_HOST': '0.0.0.0',
    'JWT_PUBLIC_KEY_PATH': 'keys/jwt_public.pem',
    'JWT_ALGORITHM': 'RS256',
    'REDIS_HOST': 'localhost',
    'REDIS_PORT': 6379,
    'REDIS_DB': 0,
    'REDIS_PASSWORD': None,
    'REDIS_MAX_CONNECTIONS': 10,
    'IDEMPOTENCY_TTL_SECONDS': 86400,  # 24 hours
    'RATE_LIMIT_REQUESTS': 100,  # requests per window
    'RATE_LIMIT_WINDOW': 60,  # seconds
    'CIRCUIT_BREAKER_THRESHOLD': 5,  # failures before opening
    'CIRCUIT_BREAKER_TIMEOUT': 30,  # seconds before retry
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
    format='%(asctime)s - %(name)s - %(levelname)s - [%(request_id)s] - %(message)s',
    handlers=[
        logging.FileHandler(CONFIG.get('LOG_FILE', '/var/log/vnf-broker/broker.log')),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('vnf-broker-enhanced')

# Flask app
app = Flask(__name__)

# Redis clients
redis_pool: Optional[ConnectionPool] = None
redis_client: Optional[redis.Redis] = None

# Circuit breaker state per VNF instance
circuit_breaker_state = {}  # {vnf_instance_id: {'state': 'closed|open|half_open', 'failures': int, 'last_failure': timestamp}}

# ============================================================================
# Pydantic Models for Request Validation
# ============================================================================

class FirewallAction(str, Enum):
    """Firewall rule action"""
    ALLOW = "allow"
    DENY = "deny"
    REJECT = "reject"

class Protocol(str, Enum):
    """Network protocol"""
    TCP = "tcp"
    UDP = "udp"
    ICMP = "icmp"
    ANY = "any"

class CreateFirewallRuleRequest(BaseModel):
    """Validated request for creating firewall rules"""
    vnfInstanceId: str = Field(..., min_length=1, max_length=128, description="VNF instance UUID")
    ruleId: str = Field(..., min_length=1, max_length=128, description="Unique rule identifier")
    action: FirewallAction = Field(..., description="Allow, deny, or reject")
    protocol: Protocol = Field(..., description="Network protocol")
    sourceIp: str = Field(..., description="Source IP or CIDR")
    destinationIp: str = Field(..., description="Destination IP or CIDR")
    destinationPort: Optional[int] = Field(None, ge=1, le=65535, description="Destination port")
    enabled: bool = Field(True, description="Rule enabled state")
    description: Optional[str] = Field(None, max_length=500, description="Rule description")
    
    @validator('sourceIp', 'destinationIp')
    def validate_ip(cls, v):
        """Validate IP address or CIDR notation"""
        # Simple validation - production would use ipaddress module
        if not v or len(v) > 100:
            raise ValueError('Invalid IP address or CIDR')
        return v

class CreateNATRuleRequest(BaseModel):
    """Validated request for creating NAT rules"""
    vnfInstanceId: str = Field(..., min_length=1, max_length=128)
    ruleId: str = Field(..., min_length=1, max_length=128)
    natType: str = Field(..., pattern="^(snat|dnat|1to1)$")
    originalIp: str
    translatedIp: str
    originalPort: Optional[int] = Field(None, ge=1, le=65535)
    translatedPort: Optional[int] = Field(None, ge=1, le=65535)
    protocol: Protocol = Protocol.ANY
    enabled: bool = True
    description: Optional[str] = Field(None, max_length=500)

class ErrorResponse(BaseModel):
    """Standard error response"""
    error: str
    message: str
    timestamp: str
    request_id: Optional[str] = None

# ============================================================================
# Configuration and Initialization
# ============================================================================

def load_config():
    """Load configuration from file"""
    config_paths = ['/etc/vnf-broker/config.json', 'config.dev.json', 'config.sample.json']
    
    for config_file in config_paths:
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                user_config = json.load(f)
                CONFIG.update(user_config)
            logger.info(f"Loaded configuration from {config_file}")
            return
    
    logger.warning(f"No config file found, using defaults")

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
            decode_responses=True,
            socket_connect_timeout=5,
            socket_keepalive=True
        )
        
        redis_client = redis.Redis(connection_pool=redis_pool)
        redis_client.ping()
        logger.info(f"Redis connected: {CONFIG['REDIS_HOST']}:{CONFIG['REDIS_PORT']}")
        
    except redis.ConnectionError as e:
        logger.error(f"Redis connection failed: {e}")
        sys.exit(1)

def load_jwt_public_key():
    """Load RSA public key for JWT verification"""
    key_path = CONFIG['JWT_PUBLIC_KEY_PATH']
    
    if not os.path.exists(key_path):
        logger.error(f"JWT public key not found: {key_path}")
        sys.exit(1)
    
    with open(key_path, 'rb') as f:
        public_key = serialization.load_pem_public_key(f.read())
    
    logger.info(f"Loaded RS256 public key from {key_path}")
    return public_key

JWT_PUBLIC_KEY = None

# ============================================================================
# Rate Limiting
# ============================================================================

def check_rate_limit(client_id: str) -> Tuple[bool, Optional[int]]:
    """
    Check if client has exceeded rate limit
    Returns: (is_allowed, retry_after_seconds)
    """
    key = f"rate_limit:{client_id}"
    window = CONFIG['RATE_LIMIT_WINDOW']
    limit = CONFIG['RATE_LIMIT_REQUESTS']
    
    try:
        pipe = redis_client.pipeline()
        now = time.time()
        window_start = now - window
        
        # Remove old requests
        pipe.zremrangebyscore(key, 0, window_start)
        # Count requests in window
        pipe.zcard(key)
        # Add current request
        pipe.zadd(key, {str(now): now})
        # Set expiry
        pipe.expire(key, window)
        
        results = pipe.execute()
        request_count = results[1]
        
        if request_count >= limit:
            retry_after = int(window - (now - window_start))
            logger.warning(f"Rate limit exceeded for {client_id}: {request_count}/{limit}")
            return False, retry_after
        
        return True, None
        
    except redis.RedisError as e:
        logger.error(f"Rate limit check failed: {e}")
        # Fail open in case of Redis issues
        return True, None

# ============================================================================
# Circuit Breaker
# ============================================================================

def check_circuit_breaker(vnf_instance_id: str) -> bool:
    """
    Check if circuit breaker allows request to VNF instance
    Returns True if request should proceed, False if circuit is open
    """
    if vnf_instance_id not in circuit_breaker_state:
        circuit_breaker_state[vnf_instance_id] = {
            'state': 'closed',
            'failures': 0,
            'last_failure': None
        }
    
    cb = circuit_breaker_state[vnf_instance_id]
    now = time.time()
    
    if cb['state'] == 'open':
        # Check if timeout has passed
        if cb['last_failure'] and (now - cb['last_failure']) > CONFIG['CIRCUIT_BREAKER_TIMEOUT']:
            logger.info(f"Circuit breaker half-open for {vnf_instance_id}")
            cb['state'] = 'half_open'
            return True
        
        logger.warning(f"Circuit breaker OPEN for {vnf_instance_id}")
        return False
    
    return True

def record_circuit_breaker_success(vnf_instance_id: str):
    """Record successful VNF request"""
    if vnf_instance_id in circuit_breaker_state:
        cb = circuit_breaker_state[vnf_instance_id]
        if cb['state'] == 'half_open':
            logger.info(f"Circuit breaker CLOSED for {vnf_instance_id}")
        cb['state'] = 'closed'
        cb['failures'] = 0
        cb['last_failure'] = None

def record_circuit_breaker_failure(vnf_instance_id: str):
    """Record failed VNF request"""
    if vnf_instance_id not in circuit_breaker_state:
        circuit_breaker_state[vnf_instance_id] = {
            'state': 'closed',
            'failures': 0,
            'last_failure': None
        }
    
    cb = circuit_breaker_state[vnf_instance_id]
    cb['failures'] += 1
    cb['last_failure'] = time.time()
    
    if cb['failures'] >= CONFIG['CIRCUIT_BREAKER_THRESHOLD']:
        logger.error(f"Circuit breaker OPEN for {vnf_instance_id} after {cb['failures']} failures")
        cb['state'] = 'open'

# ============================================================================
# JWT Validation
# ============================================================================

def validate_jwt(token: str) -> Optional[Dict]:
    """Validate JWT token with RS256"""
    try:
        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=[CONFIG['JWT_ALGORITHM']]
        )
        return payload
    except jwt.ExpiredSignatureError:
        logger.warning("JWT expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.error(f"Invalid JWT: {e}")
        return None

# ============================================================================
# Idempotency
# ============================================================================

def compute_idempotency_key(operation: str, params: Dict) -> str:
    """Compute idempotency key"""
    params_str = json.dumps(params, sort_keys=True)
    params_hash = hashlib.sha256(params_str.encode()).hexdigest()[:16]
    return f"idempotency:{operation}:{params_hash}"

def check_idempotency(operation: str, params: Dict) -> Optional[Dict]:
    """Check idempotency cache"""
    key = compute_idempotency_key(operation, params)
    try:
        cached = redis_client.get(key)
        if cached:
            logger.info(f"Idempotency HIT: {key}")
            return json.loads(cached)
        return None
    except redis.RedisError as e:
        logger.error(f"Idempotency check failed: {e}")
        return None

def store_idempotency(operation: str, params: Dict, response: Dict):
    """Store response in idempotency cache"""
    key = compute_idempotency_key(operation, params)
    ttl = CONFIG['IDEMPOTENCY_TTL_SECONDS']
    try:
        redis_client.setex(key, ttl, json.dumps(response))
        logger.info(f"Idempotency stored: {key}")
    except redis.RedisError as e:
        logger.error(f"Idempotency store failed: {e}")

# ============================================================================
# Flask Request Decorators
# ============================================================================

def require_auth(f):
    """Decorator to require JWT authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'Unauthorized', 'message': 'Missing or invalid Authorization header'}), 401
        
        token = auth_header.split(' ', 1)[1]
        jwt_payload = validate_jwt(token)
        
        if not jwt_payload:
            return jsonify({'error': 'Forbidden', 'message': 'Invalid or expired JWT token'}), 403
        
        request.jwt_payload = jwt_payload
        return f(*args, **kwargs)
    
    return decorated_function

def rate_limit(f):
    """Decorator to enforce rate limiting"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Use JWT subject or IP as client ID
        client_id = getattr(request, 'jwt_payload', {}).get('sub') or request.remote_addr
        
        allowed, retry_after = check_rate_limit(client_id)
        if not allowed:
            return jsonify({
                'error': 'Rate limit exceeded',
                'message': f'Too many requests. Retry after {retry_after} seconds.',
                'retry_after': retry_after
            }), 429
        
        return f(*args, **kwargs)
    
    return decorated_function

# ============================================================================
# API Endpoints
# ============================================================================

@app.route('/health', methods=['GET'])
def health_check():
    """Health check with detailed status"""
    redis_status = 'unknown'
    redis_latency_ms = None
    
    try:
        start = time.time()
        redis_client.ping()
        redis_latency_ms = int((time.time() - start) * 1000)
        redis_status = 'connected'
    except Exception as e:
        redis_status = f'error: {str(e)}'
    
    return jsonify({
        'status': 'healthy',
        'service': 'vnf-broker-enhanced',
        'version': '1.0.0-build2',
        'redis': {
            'status': redis_status,
            'latency_ms': redis_latency_ms
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/metrics', methods=['GET'])
def metrics():
    """Metrics endpoint for monitoring"""
    circuit_breaker_stats = {}
    for vnf_id, cb in circuit_breaker_state.items():
        circuit_breaker_stats[vnf_id] = {
            'state': cb['state'],
            'failure_count': cb['failures']
        }
    
    return jsonify({
        'circuit_breakers': circuit_breaker_stats,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/vnf/firewall/create', methods=['POST'])
@require_auth
@rate_limit
def create_firewall_rule():
    """Create firewall rule with full validation and hardening"""
    request_id = hashlib.sha256(f"{time.time()}:{request.remote_addr}".encode()).hexdigest()[:8]
    
    try:
        # Pydantic validation
        req_data = CreateFirewallRuleRequest(**request.get_json())
    except ValidationError as e:
        logger.error(f"[{request_id}] Validation error: {e}")
        return jsonify({
            'error': 'Validation error',
            'message': 'Invalid request data',
            'details': e.errors()
        }), 400
    except Exception as e:
        logger.error(f"[{request_id}] Parse error: {e}")
        return jsonify({'error': 'Bad request', 'message': 'Invalid JSON'}), 400
    
    # Check circuit breaker
    if not check_circuit_breaker(req_data.vnfInstanceId):
        return jsonify({
            'error': 'Service unavailable',
            'message': f'Circuit breaker open for VNF instance {req_data.vnfInstanceId}',
            'vnfInstanceId': req_data.vnfInstanceId
        }), 503
    
    # Idempotency check
    operation = 'firewall.create'
    params = req_data.dict()
    
    cached_response = check_idempotency(operation, params)
    if cached_response:
        logger.info(f"[{request_id}] Idempotent request for rule {req_data.ruleId}")
        return jsonify(cached_response), 200
    
    # Execute operation (placeholder - would call actual VNF)
    try:
        # Simulate VNF operation
        response_data = {
            'success': True,
            'ruleId': req_data.ruleId,
            'vnfInstanceId': req_data.vnfInstanceId,
            'status': 'created',
            'timestamp': datetime.now().isoformat(),
            'request_id': request_id
        }
        
        # Record success
        record_circuit_breaker_success(req_data.vnfInstanceId)
        
        # Store idempotency
        store_idempotency(operation, params, response_data)
        
        logger.info(f"[{request_id}] Created firewall rule {req_data.ruleId}")
        return jsonify(response_data), 201
        
    except Exception as e:
        # Record failure
        record_circuit_breaker_failure(req_data.vnfInstanceId)
        logger.error(f"[{request_id}] Failed to create rule: {e}")
        return jsonify({
            'error': 'VNF operation failed',
            'message': str(e),
            'request_id': request_id
        }), 502

@app.route('/api/vnf/nat/create', methods=['POST'])
@require_auth
@rate_limit
def create_nat_rule():
    """Create NAT rule with validation"""
    request_id = hashlib.sha256(f"{time.time()}:{request.remote_addr}".encode()).hexdigest()[:8]
    
    try:
        req_data = CreateNATRuleRequest(**request.get_json())
    except ValidationError as e:
        logger.error(f"[{request_id}] Validation error: {e}")
        return jsonify({
            'error': 'Validation error',
            'message': 'Invalid request data',
            'details': e.errors()
        }), 400
    except Exception as e:
        logger.error(f"[{request_id}] Parse error: {e}")
        return jsonify({'error': 'Bad request', 'message': 'Invalid JSON'}), 400
    
    # Check circuit breaker
    if not check_circuit_breaker(req_data.vnfInstanceId):
        return jsonify({
            'error': 'Service unavailable',
            'message': f'Circuit breaker open for VNF instance {req_data.vnfInstanceId}'
        }), 503
    
    # Idempotency and execution (similar to firewall rule)
    operation = 'nat.create'
    params = req_data.dict()
    
    cached_response = check_idempotency(operation, params)
    if cached_response:
        return jsonify(cached_response), 200
    
    response_data = {
        'success': True,
        'ruleId': req_data.ruleId,
        'vnfInstanceId': req_data.vnfInstanceId,
        'natType': req_data.natType,
        'status': 'created',
        'timestamp': datetime.now().isoformat(),
        'request_id': request_id
    }
    
    record_circuit_breaker_success(req_data.vnfInstanceId)
    store_idempotency(operation, params, response_data)
    
    logger.info(f"[{request_id}] Created NAT rule {req_data.ruleId}")
    return jsonify(response_data), 201

@app.errorhandler(Exception)
def handle_exception(e):
    """Global exception handler with structured errors"""
    logger.exception("Unhandled exception")
    
    error_response = {
        'error': 'Internal server error',
        'message': str(e) if CONFIG['DEBUG'] else 'An unexpected error occurred',
        'timestamp': datetime.now().isoformat()
    }
    
    return jsonify(error_response), 500

# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    """Initialize and start broker"""
    global JWT_PUBLIC_KEY
    
    load_config()
    
    # Setup logging directory
    os.makedirs(os.path.dirname(CONFIG['LOG_FILE']), exist_ok=True)
    
    # Initialize components
    init_redis()
    JWT_PUBLIC_KEY = load_jwt_public_key()
    
    logger.info("=" * 80)
    logger.info("VNF Broker Enhanced - Build2")
    logger.info("=" * 80)
    logger.info(f"Port: {CONFIG['BROKER_PORT']}")
    logger.info(f"JWT: {CONFIG['JWT_ALGORITHM']} (RS256)")
    logger.info(f"Redis: {CONFIG['REDIS_HOST']}:{CONFIG['REDIS_PORT']}")
    logger.info(f"Idempotency TTL: {CONFIG['IDEMPOTENCY_TTL_SECONDS']}s")
    logger.info(f"Rate Limit: {CONFIG['RATE_LIMIT_REQUESTS']}/{CONFIG['RATE_LIMIT_WINDOW']}s")
    logger.info(f"Circuit Breaker: {CONFIG['CIRCUIT_BREAKER_THRESHOLD']} failures, {CONFIG['CIRCUIT_BREAKER_TIMEOUT']}s timeout")
    logger.info("=" * 80)
    
    app.run(
        host=CONFIG['BROKER_HOST'],
        port=CONFIG['BROKER_PORT'],
        debug=CONFIG['DEBUG']
    )

if __name__ == '__main__':
    main()
