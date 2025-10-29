#!/bin/bash
# install_git_hooks.sh - Configure repo to use .githooks as hooksPath
set -euo pipefail
REPO_DIR="${1:-/root/Build}"
cd "$REPO_DIR"
chmod +x .githooks/pre-commit || true
chmod +x .githooks/pre-push || true
git config core.hooksPath .githooks
echo "Git hooks installed (pre-commit, pre-push; core.hooksPath=.githooks)"
