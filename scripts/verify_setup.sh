#!/bin/bash
################################################################################
# Script: verify_setup.sh
# Purpose: Verify build server setup and prerequisites
# Usage: ./verify_setup.sh [server_id]
#
# Arguments:
#   server_id - build1, build2, build3, or build4 (optional, auto-detects)
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
#
# Dependencies: jq, git, ssh
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="/root/Build"
SERVER_ID="${1:-$(hostname | grep -oP 'build\\d+' || echo 'unknown')}"
FAILURE_COUNT=0

# Logging functions
log_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}"$1"${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

log_check() {
    echo -n "Checking $1... "
}

log_pass() {
    echo -e "${GREEN}[OK] PASS${NC}"
    [ -n "${1:-}" ] && echo -e "  ${GREEN}$1${NC}"
}

log_fail() {
    echo -e "${RED}✗ FAIL${NC}"
    echo -e "  ${RED}$1${NC}"
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
}

log_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}"
    echo -e "  ${YELLOW}$1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Start verification
log_header "Build Server Setup Verification"
log_info "Server ID: $SERVER_ID"
log_info "Repository: $REPO_DIR"
log_info "Date: $(date -u +%Y-%m-%d\ %H:%M:%S)"

# Check 1: System Prerequisites
log_header "System Prerequisites"

log_check "Git installation"
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | awk '{print $3}')
    log_pass "Git version $GIT_VERSION installed"
else
    log_fail "Git is not installed. Run: apt-get install git"
fi

log_check "jq installation"
if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version | cut -d'-' -f2)
    log_pass "jq version $JQ_VERSION installed"
else
    log_fail "jq is not installed. Run: apt-get install jq"
fi

log_check "SSH installation"
if command -v ssh &> /dev/null; then
    SSH_VERSION=$(ssh -V 2>&1 | awk '{print $1}')
    log_pass "$SSH_VERSION installed"
else
    log_fail "SSH is not installed. Run: apt-get install openssh-client"
fi

# Check 2: Repository Structure
log_header "Repository Structure"

log_check "Repository directory exists"
if [ -d "$REPO_DIR" ]; then
    log_pass "Found at $REPO_DIR"
    cd "$REPO_DIR"
else
    log_fail "Repository directory not found at $REPO_DIR"
    exit 1
fi

log_check "Git repository initialized"
if [ -d ".git" ]; then
    CURRENT_BRANCH=$(git branch --show-current)
    log_pass "On branch: $CURRENT_BRANCH"
else
    log_fail "Not a git repository. Run: git clone https://github.com/alexandremattioli/Build.git"
fi

REQUIRED_DIRS=("build1" "build2" "build3" "build4" "coordination" "shared" "scripts")
for dir in "${REQUIRED_DIRS[@]}"; do
    log_check "Directory: $dir"
    if [ -d "$dir" ]; then
        log_pass
    else
        log_fail "Missing directory: $dir"
    fi
done

# Summary
log_header "Verification Summary"

if [ $FAILURE_COUNT -eq 0 ]; then
    echo -e "${GREEN}[OK] All checks passed!${NC}"
    echo -e "${GREEN}Server is ready for build operations.${NC}"
    exit 0
else
    echo -e "${RED}✗ $FAILURE_COUNT check(s) failed${NC}"
    echo -e "${RED}Please fix the issues above before proceeding.${NC}"
    exit 1
fi
