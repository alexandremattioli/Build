#!/usr/bin/env bash
set -euo pipefail
python3 -m pip install --upgrade pip >/dev/null 2>&1 || true
python3 -m pip install pytest >/dev/null 2>&1 || true
pytest -q
