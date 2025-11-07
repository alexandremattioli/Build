#!/usr/bin/env python3
"""
VNF Dictionary Validator - Build2
==================================
Validates vendor dictionary YAML files against JSON Schema.
Provides fail-fast validation at broker startup with dev flag bypass.

Usage:
    python3 dictionary_validator.py dictionaries/pfsense-dictionary.yaml
    python3 dictionary_validator.py --dev dictionaries/  # Validate all, don't fail on unknown
"""

import os
import sys
import yaml
import json
import logging
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from jsonschema import validate, ValidationError, Draft7Validator
from jsonschema.exceptions import SchemaError

logger = logging.getLogger(__name__)

# Supported vendors registry
SUPPORTED_VENDORS = {
    'Netgate': ['pfSense'],
    'Fortinet': ['FortiGate'],
    'Palo Alto Networks': ['PA Series'],
    'VyOS': ['VyOS'],
}

class DictionaryValidator:
    """Validates VNF dictionary files"""
    
    def __init__(self, schema_path: str, dev_mode: bool = False):
        """
        Initialize validator with JSON Schema
        
        Args:
            schema_path: Path to JSON Schema file
            dev_mode: If True, warnings don't cause failures
        """
        self.dev_mode = dev_mode
        
        with open(schema_path, 'r') as f:
            self.schema = json.load(f)
        
        self.validator = Draft7Validator(self.schema)
        logger.info(f"Loaded schema from {schema_path}")
        
    def validate_dictionary_file(self, dict_path: str) -> Tuple[bool, List[str], List[str]]:
        """
        Validate a single dictionary file
        
        Args:
            dict_path: Path to YAML dictionary file
            
        Returns:
            (is_valid, errors, warnings)
        """
        errors = []
        warnings = []
        
        try:
            with open(dict_path, 'r') as f:
                dictionary = yaml.safe_load(f)
        except yaml.YAMLError as e:
            errors.append(f"YAML parse error: {e}")
            return False, errors, warnings
        except FileNotFoundError:
            errors.append(f"File not found: {dict_path}")
            return False, errors, warnings
        
        # Validate against schema
        try:
            validate(instance=dictionary, schema=self.schema)
        except ValidationError as e:
            errors.append(f"Schema validation failed: {e.message} at {'.'.join(str(p) for p in e.path)}")
            return False, errors, warnings
        except SchemaError as e:
            errors.append(f"Invalid schema: {e}")
            return False, errors, warnings
        
        # Check vendor is supported
        vendor = dictionary.get('vendor')
        product = dictionary.get('product')
        
        if vendor not in SUPPORTED_VENDORS:
            msg = f"Unknown vendor: {vendor}. Supported: {', '.join(SUPPORTED_VENDORS.keys())}"
            if self.dev_mode:
                warnings.append(msg)
            else:
                errors.append(msg)
        elif product not in SUPPORTED_VENDORS.get(vendor, []):
            msg = f"Unknown product: {product} for vendor {vendor}. Supported: {', '.join(SUPPORTED_VENDORS[vendor])}"
            if self.dev_mode:
                warnings.append(msg)
            else:
                errors.append(msg)
        
        # Version check
        version = dictionary.get('version', '')
        if not version:
            warnings.append("Missing version field")
        elif not self._is_valid_semver(version):
            warnings.append(f"Version '{version}' is not valid semver format")
        
        # Check services are not empty
        services = dictionary.get('services', {})
        if not services:
            errors.append("No services defined in dictionary")
        else:
            for service_name, service_def in services.items():
                if not service_def:
                    warnings.append(f"Service '{service_name}' has no operations")
                    continue
                
                # Check at least one CRUD operation
                ops = ['create', 'read', 'update', 'delete', 'list', 'get']
                if not any(op in service_def for op in ops):
                    warnings.append(f"Service '{service_name}' has no standard operations (create/read/update/delete/list/get)")
        
        is_valid = len(errors) == 0
        return is_valid, errors, warnings
    
    def validate_directory(self, dict_dir: str) -> Tuple[bool, Dict[str, Tuple[bool, List, List]]]:
        """
        Validate all YAML dictionaries in a directory
        
        Args:
            dict_dir: Directory containing dictionary files
            
        Returns:
            (all_valid, results_dict)
        """
        results = {}
        all_valid = True
        
        dict_files = list(Path(dict_dir).glob('*.yaml')) + list(Path(dict_dir).glob('*.yml'))
        
        if not dict_files:
            logger.warning(f"No YAML files found in {dict_dir}")
            return False, results
        
        for dict_file in dict_files:
            is_valid, errors, warnings = self.validate_dictionary_file(str(dict_file))
            results[str(dict_file)] = (is_valid, errors, warnings)
            
            if not is_valid:
                all_valid = False
        
        return all_valid, results
    
    @staticmethod
    def _is_valid_semver(version: str) -> bool:
        """Check if version string is valid semver"""
        import re
        pattern = r'^(\d+)\.(\d+)(\.(\d+))?([+-].+)?$'
        return re.match(pattern, version) is not None


def print_validation_results(results: Dict[str, Tuple[bool, List, List]], dev_mode: bool = False):
    """Pretty print validation results"""
    total = len(results)
    passed = sum(1 for v, _, _ in results.values() if v)
    failed = total - passed
    
    print("\n" + "=" * 80)
    print("VNF Dictionary Validation Results")
    print("=" * 80)
    
    for dict_path, (is_valid, errors, warnings) in results.items():
        dict_name = os.path.basename(dict_path)
        status = "✓ PASS" if is_valid else "✗ FAIL"
        print(f"\n{status} {dict_name}")
        
        if errors:
            print(f"  Errors:")
            for error in errors:
                print(f"    - {error}")
        
        if warnings:
            print(f"  Warnings:")
            for warning in warnings:
                print(f"    - {warning}")
    
    print("\n" + "=" * 80)
    print(f"Total: {total}  |  Passed: {passed}  |  Failed: {failed}")
    if dev_mode:
        print("Mode: DEVELOPMENT (unknown vendors allowed)")
    print("=" * 80 + "\n")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Validate VNF dictionary files')
    parser.add_argument('path', help='Path to dictionary file or directory')
    parser.add_argument('--schema', default='schemas/vnf-dictionary-schema.json',
                       help='Path to JSON Schema file')
    parser.add_argument('--dev', action='store_true',
                       help='Development mode: warnings don\'t cause failures')
    parser.add_argument('--verbose', action='store_true',
                       help='Verbose logging')
    
    args = parser.parse_args()
    
    # Setup logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Check schema exists
    if not os.path.exists(args.schema):
        logger.error(f"Schema file not found: {args.schema}")
        sys.exit(1)
    
    # Create validator
    validator = DictionaryValidator(args.schema, dev_mode=args.dev)
    
    # Validate path
    if os.path.isfile(args.path):
        # Single file
        is_valid, errors, warnings = validator.validate_dictionary_file(args.path)
        results = {args.path: (is_valid, errors, warnings)}
        all_valid = is_valid
    elif os.path.isdir(args.path):
        # Directory
        all_valid, results = validator.validate_directory(args.path)
    else:
        logger.error(f"Path not found: {args.path}")
        sys.exit(1)
    
    # Print results
    print_validation_results(results, dev_mode=args.dev)
    
    # Exit with appropriate code
    if all_valid:
        logger.info("✓ All dictionaries valid")
        sys.exit(0)
    else:
        logger.error("✗ Validation failed")
        sys.exit(1)


if __name__ == '__main__':
    main()
