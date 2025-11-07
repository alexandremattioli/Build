#!/usr/bin/env python3
"""
Mock VNF Backend Server - Build2
=================================
Simulates a pfSense/FortiGate/etc. appliance for integration testing.

This mock server allows testing the VNF broker without requiring actual
VNF hardware or VMs.

Features:
- Simulates firewall rule creation/deletion
- Simulates NAT rule operations
- Configurable latency and error injection
- State persistence (in-memory)
- Vendor-specific response formats

Usage:
    # Start mock pfSense server
    python3 mock_vnf_server.py --vendor pfsense --port 9443
    
    # Start with error injection (10% failure rate)
    python3 mock_vnf_server.py --vendor pfsense --error-rate 0.1
    
    # Start with latency simulation (100-500ms)
    python3 mock_vnf_server.py --vendor pfsense --latency 100 500
"""

import os
import sys
import time
import random
import logging
import argparse
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime
from flask import Flask, request, jsonify

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('mock-vnf')

app = Flask(__name__)

# Mock VNF state
@dataclass
class MockVNFState:
    """In-memory state for mock VNF"""
    vendor: str = 'pfsense'
    firewall_rules: Dict[str, Dict] = field(default_factory=dict)
    nat_rules: Dict[str, Dict] = field(default_factory=dict)
    error_rate: float = 0.0  # Probability of simulating errors (0.0-1.0)
    min_latency_ms: int = 0  # Minimum latency in ms
    max_latency_ms: int = 0  # Maximum latency in ms
    request_count: int = 0
    error_count: int = 0

state = MockVNFState()

def simulate_latency():
    """Simulate network latency"""
    if state.max_latency_ms > 0:
        latency = random.randint(state.min_latency_ms, state.max_latency_ms)
        time.sleep(latency / 1000.0)
        logger.debug(f"Simulated {latency}ms latency")

def should_inject_error() -> bool:
    """Determine if we should inject an error"""
    if state.error_rate > 0:
        return random.random() < state.error_rate
    return False

def get_next_rule_id(prefix: str = 'rule') -> str:
    """Generate next rule ID"""
    return f"{prefix}_{int(time.time())}_{random.randint(1000, 9999)}"

# ============================================================================
# pfSense API Endpoints
# ============================================================================

@app.route('/api/v1/firewall/rule', methods=['POST'])
def pfsense_create_firewall_rule():
    """pfSense: Create firewall rule"""
    state.request_count += 1
    simulate_latency()
    
    if should_inject_error():
        state.error_count += 1
        logger.warning("Injecting simulated error")
        return jsonify({
            'status': 'error',
            'code': 500,
            'message': 'Simulated VNF backend failure'
        }), 500
    
    data = request.get_json()
    rule_id = data.get('id') or get_next_rule_id('fw')
    
    # Store rule
    rule = {
        'id': rule_id,
        'interface': data.get('interface', 'wan'),
        'type': data.get('type', 'pass'),
        'protocol': data.get('protocol', 'tcp'),
        'src': data.get('src', 'any'),
        'dst': data.get('dst', 'any'),
        'dstport': data.get('dstport'),
        'descr': data.get('descr', ''),
        'disabled': data.get('disabled', False),
        'created_at': datetime.now().isoformat()
    }
    
    state.firewall_rules[rule_id] = rule
    logger.info(f"Created firewall rule: {rule_id}")
    
    return jsonify({
        'status': 'ok',
        'code': 200,
        'message': 'Rule created successfully',
        'data': {
            'id': rule_id,
            'tracker': int(time.time())
        }
    }), 201

@app.route('/api/v1/firewall/rule/<rule_id>', methods=['DELETE'])
def pfsense_delete_firewall_rule(rule_id):
    """pfSense: Delete firewall rule"""
    state.request_count += 1
    simulate_latency()
    
    if should_inject_error():
        state.error_count += 1
        return jsonify({
            'status': 'error',
            'code': 500,
            'message': 'Simulated VNF backend failure'
        }), 500
    
    if rule_id in state.firewall_rules:
        del state.firewall_rules[rule_id]
        logger.info(f"Deleted firewall rule: {rule_id}")
        return jsonify({
            'status': 'ok',
            'code': 200,
            'message': 'Rule deleted successfully'
        }), 200
    else:
        return jsonify({
            'status': 'error',
            'code': 404,
            'message': f'Rule {rule_id} not found'
        }), 404

@app.route('/api/v1/firewall/rule/<rule_id>', methods=['PUT'])
def pfsense_update_firewall_rule(rule_id):
    """pfSense: Update firewall rule"""
    state.request_count += 1
    simulate_latency()
    
    if should_inject_error():
        state.error_count += 1
        return jsonify({
            'status': 'error',
            'code': 500,
            'message': 'Simulated VNF backend failure'
        }), 500
    
    if rule_id not in state.firewall_rules:
        return jsonify({
            'status': 'error',
            'code': 404,
            'message': f'Rule {rule_id} not found'
        }), 404
    
    data = request.get_json()
    
    # Update rule with new data
    rule = state.firewall_rules[rule_id]
    rule.update({
        'interface': data.get('interface', rule.get('interface')),
        'type': data.get('type', rule.get('type')),
        'protocol': data.get('protocol', rule.get('protocol')),
        'src': data.get('src', rule.get('src')),
        'dst': data.get('dst', rule.get('dst')),
        'dstport': data.get('dstport', rule.get('dstport')),
        'descr': data.get('descr', rule.get('descr')),
        'disabled': data.get('disabled', rule.get('disabled')),
        'updated_at': datetime.now().isoformat()
    })
    
    logger.info(f"Updated firewall rule: {rule_id}")
    
    return jsonify({
        'status': 'ok',
        'code': 200,
        'message': 'Rule updated successfully',
        'data': {
            'id': rule_id,
            'tracker': int(time.time())
        }
    }), 200

@app.route('/api/v1/firewall/rules', methods=['GET'])
def pfsense_list_firewall_rules():
    """pfSense: List all firewall rules"""
    state.request_count += 1
    simulate_latency()
    
    if should_inject_error():
        state.error_count += 1
        return jsonify({
            'status': 'error',
            'code': 500,
            'message': 'Simulated VNF backend failure'
        }), 500
    
    rules = list(state.firewall_rules.values())
    logger.info(f"Listed {len(rules)} firewall rules")
    
    return jsonify({
        'status': 'ok',
        'code': 200,
        'message': 'Rules retrieved successfully',
        'data': {
            'rules': rules,
            'count': len(rules)
        }
    }), 200

@app.route('/api/v1/firewall/nat/outbound', methods=['POST'])
def pfsense_create_nat_rule():
    """pfSense: Create NAT rule (SNAT)"""
    state.request_count += 1
    simulate_latency()
    
    if should_inject_error():
        state.error_count += 1
        return jsonify({
            'status': 'error',
            'code': 500,
            'message': 'Simulated VNF backend failure'
        }), 500
    
    data = request.get_json()
    rule_id = data.get('id') or get_next_rule_id('nat')
    
    rule = {
        'id': rule_id,
        'interface': data.get('interface', 'wan'),
        'source': data.get('source', 'any'),
        'destination': data.get('destination', 'any'),
        'target': data.get('target', ''),
        'natport': data.get('natport'),
        'descr': data.get('descr', ''),
        'disabled': data.get('disabled', False),
        'created_at': datetime.now().isoformat()
    }
    
    state.nat_rules[rule_id] = rule
    logger.info(f"Created NAT rule: {rule_id}")
    
    return jsonify({
        'status': 'ok',
        'code': 200,
        'message': 'NAT rule created successfully',
        'data': {
            'id': rule_id
        }
    }), 201

@app.route('/api/v1/firewall/nat/outbound/<rule_id>', methods=['DELETE'])
def pfsense_delete_nat_rule(rule_id):
    """pfSense: Delete NAT rule"""
    state.request_count += 1
    simulate_latency()
    
    if should_inject_error():
        state.error_count += 1
        return jsonify({
            'status': 'error',
            'code': 500,
            'message': 'Simulated VNF backend failure'
        }), 500
    
    if rule_id in state.nat_rules:
        del state.nat_rules[rule_id]
        logger.info(f"Deleted NAT rule: {rule_id}")
        return jsonify({
            'status': 'ok',
            'code': 200,
            'message': 'NAT rule deleted successfully'
        }), 200
    else:
        return jsonify({
            'status': 'error',
            'code': 404,
            'message': f'NAT rule {rule_id} not found'
        }), 404

# ============================================================================
# Mock Server Control & Status Endpoints
# ============================================================================

@app.route('/mock/status', methods=['GET'])
def mock_status():
    """Get mock server status"""
    return jsonify({
        'vendor': state.vendor,
        'firewall_rules': len(state.firewall_rules),
        'nat_rules': len(state.nat_rules),
        'total_requests': state.request_count,
        'error_count': state.error_count,
        'error_rate_configured': state.error_rate,
        'latency_range_ms': [state.min_latency_ms, state.max_latency_ms] if state.max_latency_ms > 0 else None,
        'uptime': 'mock'
    })

@app.route('/mock/rules', methods=['GET'])
def mock_list_rules():
    """List all rules in mock VNF"""
    return jsonify({
        'firewall_rules': list(state.firewall_rules.values()),
        'nat_rules': list(state.nat_rules.values())
    })

@app.route('/mock/reset', methods=['POST'])
def mock_reset():
    """Reset mock VNF state"""
    state.firewall_rules.clear()
    state.nat_rules.clear()
    state.request_count = 0
    state.error_count = 0
    logger.info("Mock VNF state reset")
    return jsonify({'status': 'ok', 'message': 'State reset'})

@app.route('/mock/config', methods=['POST'])
def mock_configure():
    """Update mock server configuration"""
    data = request.get_json()
    
    if 'error_rate' in data:
        state.error_rate = float(data['error_rate'])
        logger.info(f"Error rate set to {state.error_rate}")
    
    if 'latency' in data:
        state.min_latency_ms = int(data['latency'][0])
        state.max_latency_ms = int(data['latency'][1])
        logger.info(f"Latency range set to {state.min_latency_ms}-{state.max_latency_ms}ms")
    
    return jsonify({
        'status': 'ok',
        'config': {
            'error_rate': state.error_rate,
            'latency_ms': [state.min_latency_ms, state.max_latency_ms]
        }
    })

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({
        'status': 'healthy',
        'vendor': state.vendor,
        'type': 'mock-vnf'
    })

# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Mock VNF backend server for testing')
    parser.add_argument('--vendor', default='pfsense',
                       choices=['pfsense', 'fortigate', 'vyos', 'paloalto'],
                       help='Vendor to simulate')
    parser.add_argument('--port', type=int, default=9443,
                       help='Port to listen on')
    parser.add_argument('--host', default='0.0.0.0',
                       help='Host to bind to')
    parser.add_argument('--error-rate', type=float, default=0.0,
                       help='Error injection rate (0.0-1.0)')
    parser.add_argument('--latency', nargs=2, type=int, metavar=('MIN', 'MAX'),
                       help='Latency range in ms (e.g., --latency 100 500)')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug logging')
    
    args = parser.parse_args()
    
    # Configure state
    state.vendor = args.vendor
    state.error_rate = args.error_rate
    
    if args.latency:
        state.min_latency_ms = args.latency[0]
        state.max_latency_ms = args.latency[1]
    
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
    
    logger.info("=" * 80)
    logger.info(f"Mock VNF Server - {args.vendor.upper()}")
    logger.info("=" * 80)
    logger.info(f"Vendor: {args.vendor}")
    logger.info(f"Listen: {args.host}:{args.port}")
    logger.info(f"Error rate: {args.error_rate * 100}%")
    if args.latency:
        logger.info(f"Latency: {args.latency[0]}-{args.latency[1]}ms")
    logger.info("=" * 80)
    logger.info("")
    logger.info("Control endpoints:")
    logger.info(f"  GET  http://localhost:{args.port}/mock/status")
    logger.info(f"  GET  http://localhost:{args.port}/mock/rules")
    logger.info(f"  POST http://localhost:{args.port}/mock/reset")
    logger.info(f"  POST http://localhost:{args.port}/mock/config")
    logger.info("")
    logger.info("VNF API endpoints (pfSense):")
    logger.info(f"  POST   http://localhost:{args.port}/api/v1/firewall/rule")
    logger.info(f"  PUT    http://localhost:{args.port}/api/v1/firewall/rule/<id>")
    logger.info(f"  DELETE http://localhost:{args.port}/api/v1/firewall/rule/<id>")
    logger.info(f"  GET    http://localhost:{args.port}/api/v1/firewall/rules")
    logger.info(f"  POST   http://localhost:{args.port}/api/v1/firewall/nat/outbound")
    logger.info("=" * 80)
    
    app.run(host=args.host, port=args.port, debug=args.debug)

if __name__ == '__main__':
    main()
