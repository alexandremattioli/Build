#!/usr/bin/env python3
"""
Test Runner for Build Infrastructure
Run with: python run_tests.py
"""

import sys
import unittest
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

def run_tests():
    """Discover and run all tests in the tests directory"""
    loader = unittest.TestLoader()
    start_dir = Path(__file__).parent / 'tests'
    
    if not start_dir.exists():
        print(f"Error: Test directory not found: {start_dir}")
        return False
    
    suite = loader.discover(str(start_dir), pattern='test_*.py')
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    print("\n" + "="*70)
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Skipped: {len(result.skipped)}")
    print("="*70)
    
    return result.wasSuccessful()

if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
