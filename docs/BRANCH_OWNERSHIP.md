# CloudStack Branch Ownership and Usage

This document clarifies which CloudStack branches are owned by each builder and which are shared. It applies to the CloudStack repository cloned at `/root/src/cloudstack`.

## Remotes

- origin: https://github.com/alexandremattioli/cloudstack.git (your fork)
- upstream: https://github.com/shapeblue/cloudstack.git (upstream)

## Branch ownership

- Build2 (Copilot) OWNED branches:
  - `Copilot`
  - `VNFCoPilot` (current working branch)

- Build1 (Codex) OWNED branches:
  - `VNFCodex`
  - **Naming convention:** any new Codex-owned branch must include `Codex` in the branch name (e.g., `feature/Codex-sync-fixes`) so ownership is obvious in shared tooling.

- Shared/baseline branches:
  - `main` (baseline)
  - `VNFCopilot` (Build2 working branch per instructions)

Notes:
- Build2 currently works from `origin/ExternalNew` as per Build2 instructions (`/root/Build/build2/BUILD_INSTRUCTIONS.md`).
- Local checkout can track `upstream/main` for baseline while feature work happens on your fork branches.

## Quick commands

List branches on your fork (origin):

```bash
cd /root/src/cloudstack
git fetch origin --prune
git ls-remote --heads origin
```

Check out a Copilot-owned branch locally and set tracking:

```bash
git checkout -B Copilot origin/Copilot
```

Return to VNFCopilot (Build2 working branch):

```bash
git checkout -B VNFCopilot origin/VNFCopilot
```

Track upstream main for baseline sync:

```bash
git checkout -B main upstream/main
```

## Current state (Build2)

- Local branch `ExternalNew` was previously checked out; currently the local branch may be removed, but `origin/ExternalNew` remains available.
- Active branch now: `main` (tracking `upstream/main`). Use the commands above to switch back to `ExternalNew` when needed.
