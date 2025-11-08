#!/usr/bin/env python3
"""Hive shared utilities for unit testing and logic reuse.
Includes role suggestion logic and message signing/validation helpers.
"""
from collections import Counter
import json, hmac, hashlib

MAGIC = "BUILD/HELLO/v1"


def suggest_cloudstack_role(peers, vnf_available=False):
    """Suggest a role based on current peers.
    peers: list of dicts with 'role' or nested identity role
    vnf_available: bool indicating if a VNF broker is reachable
    Returns dict: {role, packages, config, reason}
    """
    roles = Counter((p.get('role') or (p.get('identity') or {}).get('role') or 'unknown') for p in peers)
    if roles.get('management-server', 0) == 0:
        return {
            'role': 'management-server',
            'packages': ['mysql-server','nfs-kernel-server','openjdk-17-jdk','git'],
            'config': {'db': 'mysql', 'nfs': True},
            'reason': 'First management server needed'
        }
    if roles.get('cloudstack-builder', 0) < 2:
        return {
            'role': 'cloudstack-builder',
            'packages': ['openjdk-17-jdk','maven','git','build-essential'],
            'config': {'build_threads': 8},
            'reason': 'Increase build capacity'
        }
    if roles.get('kvm-hypervisor', 0) == 0:
        return {
            'role': 'kvm-hypervisor',
            'packages': ['qemu-kvm','libvirt-daemon-system','bridge-utils'],
            'config': {'virt_network': 'default'},
            'reason': 'Provide hypervisor for functional tests'
        }
    if vnf_available and roles.get('vnf-tester', 0) == 0:
        return {
            'role': 'vnf-tester',
            'packages': ['python3-requests','docker.io'],
            'config': {'broker_port': 8443},
            'reason': 'Validate VNF broker operations'
        }
    return {
        'role': 'test-runner',
        'packages': ['python3-pytest','curl','git'],
        'config': {'parallel': 4},
        'reason': 'Expand test execution capacity'
    }


def sign(payload_bytes: bytes, secret: bytes) -> str:
    """HMAC-SHA256 sign a bytes payload with secret; returns hex digest"""
    if not secret:
        return ''
    return hmac.new(secret, payload_bytes, hashlib.sha256).hexdigest()


def valid(message: dict, secret: bytes, magic: str = MAGIC) -> bool:
    """Validate message envelope of form {magic, payload, sig} using secret."""
    if message.get('magic') != magic:
        return False
    pl = message.get('payload')
    sig = message.get('sig', '')
    if not isinstance(pl, dict):
        return False
    raw = json.dumps(pl, separators=(',',':')).encode('utf-8')
    if secret:
        mac = hmac.new(secret, raw, hashlib.sha256).hexdigest()
        return hmac.compare_digest(mac, sig)
    return True
