#!/bin/bash
# Test runner for Build Infrastructure (Linux/Mac)

set -e

echo "Looking for Python installation..."

if command -v python3 &> /dev/null; then
    echo "Found Python3"
    python3 --version
    echo ""
    echo "Running tests..."
    python3 run_tests.py
    exit $?
elif command -v python &> /dev/null; then
    echo "Found Python"
    python --version
    echo ""
    echo "Running tests..."
    python run_tests.py
    exit $?
else
    echo "ERROR: Python not found in PATH"
    echo "Please install Python 3.8+ and try again"
    exit 1
fi
