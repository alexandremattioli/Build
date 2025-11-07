#!/usr/bin/env python3
"""
VNF Dictionary Version Compatibility Checker - Build2
======================================================
Checks if a dictionary version is compatible with broker version.

Usage:
    python3 version_checker.py dictionaries/pfsense-dictionary.yaml --broker-version 1.0.0
    python3 version_checker.py --dict-version 1.1.0 --broker-version 1.0.0
"""

import sys
import yaml
import argparse
from typing import Tuple

def parse_semver(version: str) -> Tuple[int, int, int]:
    """Parse semantic version string into (major, minor, patch)"""
    parts = version.split('.')
    major = int(parts[0]) if len(parts) > 0 else 0
    minor = int(parts[1]) if len(parts) > 1 else 0
    patch = int(parts[2]) if len(parts) > 2 else 0
    return (major, minor, patch)

def compare_versions(v1: str, v2: str) -> int:
    """
    Compare two semantic versions.
    Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
    """
    p1 = parse_semver(v1)
    p2 = parse_semver(v2)
    
    if p1 < p2:
        return -1
    elif p1 > p2:
        return 1
    else:
        return 0

def check_compatibility(dict_version: str, broker_version: str, min_broker_version: str = None) -> Tuple[bool, str]:
    """
    Check if dictionary version is compatible with broker version.
    
    Rules:
    1. Dictionary major version must not exceed broker major version
    2. If min_broker_version specified, broker must meet or exceed it
    3. Within same major version, all minor versions are backward compatible
    
    Returns: (is_compatible, reason)
    """
    dict_major, dict_minor, dict_patch = parse_semver(dict_version)
    broker_major, broker_minor, broker_patch = parse_semver(broker_version)
    
    # Rule 1: Dictionary major version must not exceed broker major version
    if dict_major > broker_major:
        return False, f"Dictionary v{dict_version} requires broker v{dict_major}.x.x or higher (current: v{broker_version})"
    
    # Rule 2: Check minimum broker version if specified
    if min_broker_version:
        cmp = compare_versions(broker_version, min_broker_version)
        if cmp < 0:
            return False, f"Dictionary requires minimum broker version {min_broker_version} (current: {broker_version})"
    
    # Rule 3: Within same major version, backward compatible
    if dict_major < broker_major:
        return True, f"Dictionary v{dict_version} is backward compatible with broker v{broker_version}"
    
    # Same major version
    if dict_minor <= broker_minor:
        return True, f"Dictionary v{dict_version} is compatible with broker v{broker_version}"
    else:
        return True, f"Dictionary v{dict_version} may use features not available in broker v{broker_version} (warning)"

def load_dictionary_version(path: str) -> Tuple[str, str]:
    """Load version and min_broker_version from dictionary file"""
    try:
        with open(path, 'r') as f:
            data = yaml.safe_load(f)
        
        version = data.get('version', '1.0.0')
        min_broker = data.get('compatibility', {}).get('min_broker_version')
        
        return version, min_broker
    except Exception as e:
        raise ValueError(f"Failed to load dictionary: {e}")

def main():
    parser = argparse.ArgumentParser(description='Check VNF dictionary version compatibility')
    parser.add_argument('dictionary', nargs='?', help='Path to dictionary YAML file')
    parser.add_argument('--dict-version', help='Dictionary version (if not loading from file)')
    parser.add_argument('--broker-version', required=True, help='Broker version to check against')
    parser.add_argument('--verbose', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    # Get dictionary version
    if args.dictionary:
        dict_version, min_broker = load_dictionary_version(args.dictionary)
        print(f"Dictionary: {args.dictionary}")
        print(f"  Version: {dict_version}")
        if min_broker:
            print(f"  Minimum broker version: {min_broker}")
    elif args.dict_version:
        dict_version = args.dict_version
        min_broker = None
        print(f"Dictionary version: {dict_version}")
    else:
        print("Error: Must provide either dictionary file or --dict-version", file=sys.stderr)
        sys.exit(1)
    
    print(f"Broker version: {args.broker_version}")
    print()
    
    # Check compatibility
    is_compatible, reason = check_compatibility(dict_version, args.broker_version, min_broker)
    
    if is_compatible:
        print(f"✓ COMPATIBLE: {reason}")
        sys.exit(0)
    else:
        print(f"✗ INCOMPATIBLE: {reason}")
        sys.exit(1)

if __name__ == '__main__':
    main()
