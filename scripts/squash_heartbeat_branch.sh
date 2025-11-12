#!/bin/bash
################################################################################
# Script: squash_heartbeat_branch.sh
# Purpose: Squash a heartbeat branch history into a single commit (keeping
#          current snapshot), optionally creating a remote backup ref.
# Usage:
#   ./squash_heartbeat_branch.sh --branch <branch>
#   ./squash_heartbeat_branch.sh --server <build1|build2>
# Options:
#   --branch BRANCH   Target branch to squash (e.g., heartbeat-build2)
#   --server ID       Use branch "heartbeat-<ID>" (ID: build1|build2)
#   --backup          Push a backup copy to origin as backup/<branch>-<timestamp>
#   --dry-run         Print planned operations without making changes
#   --push            Push changes after squashing (default: true)
#   --no-push         Do not push changes
# Notes:
# - This uses git plumbing to avoid switching your working branch.
# - Requires permission to force-push the target branch on origin.
################################################################################
set -euo pipefail

REPO_DIR="${REPO_DIR:-/root/Build}"
cd "$REPO_DIR"

branch=""
server=""
backup=false
push_changes=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      branch="$2"; shift 2;;
    --server)
      server="$2"; shift 2;;
    --backup)
      backup=true; shift;;
    --dry-run)
      DRY_RUN=true; shift;;
    --push)
      push_changes=true; shift;;
    --no-push)
      push_changes=false; shift;;
    *)
      echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ -n "${server}" && -z "${branch}" ]]; then
  if [[ ! "$server" =~ ^(build1|build2)$ ]]; then
    echo "ERROR: --server must be build1 or build2" >&2; exit 1
  fi
  branch="heartbeat-$server"
fi

if [[ -z "$branch" ]]; then
  echo "Usage: $0 --branch <branch> | --server <build1|build2> [--backup] [--dry-run] [--no-push]" >&2
  exit 1
fi

# Ensure we have latest refs
if ! $DRY_RUN; then
  git fetch origin "$branch:$branch" || {
    echo "ERROR: Branch '$branch' not found on origin" >&2; exit 1;
  }
else
  echo "[dry-run] git fetch origin $branch:$branch"
fi

# Get the tree of current head of the branch
if $DRY_RUN; then
  echo "[dry-run] Resolve tree for $branch"
  tree_id="<computed>"
else
  tree_id=$(git rev-parse "$branch^{tree}")
fi

# Create a backup ref if requested
TS=$(date -u +%Y%m%d%H%M%S)
backup_ref="refs/heads/backup/${branch}-${TS}"
if $backup; then
  if $DRY_RUN; then
    echo "[dry-run] git push origin refs/heads/$branch:$backup_ref"
  else
    git push origin "refs/heads/$branch:$backup_ref" || echo "WARN: backup push failed (continuing)"
  fi
fi

# Create a single squashed commit with the same tree
if $DRY_RUN; then
  echo "[dry-run] new_commit=\$(echo 'Squashed \$branch on \$(date -u)' | git commit-tree <tree>)"
  echo "[dry-run] update local ref refs/heads/$branch to new_commit"
else
  new_commit=$(printf "Squashed %s on %s\n" "$branch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | git commit-tree "$tree_id")
  git update-ref "refs/heads/$branch" "$new_commit"
fi

# Push with retry
push_with_retry() {
  local refspec="refs/heads/$branch:refs/heads/$branch"
  local max_attempts=5
  local attempt=1
  local delay=1
  while [ $attempt -le $max_attempts ]; do
    if git push --force-with-lease origin "$refspec" 2>/dev/null; then
      return 0
    fi
    echo "Push failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
    sleep $delay
    git fetch origin "$branch:$branch" || true
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
  [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "squash_heartbeat_branch" "git push failed after $max_attempts attempts"
  echo "ERROR: git push failed after $max_attempts attempts" >&2
  return 1
}

if $push_changes; then
  if $DRY_RUN; then
    echo "[dry-run] git push --force-with-lease origin refs/heads/$branch:refs/heads/$branch"
  else
    push_with_retry || exit 2
    echo "[OK] Squashed branch '$branch' on origin (backup: $backup)"
  fi
else
  echo "Local ref updated for '$branch' (no push performed)"
fi
