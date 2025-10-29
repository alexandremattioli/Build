#!/bin/bash
# use_git_ssh.sh - Switch origin remote to SSH
set -euo pipefail
cd /root/Build
git remote set-url origin git@github.com:alexandremattioli/Build.git
echo "Origin set to SSH: $(git remote get-url origin)"
