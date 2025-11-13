# Builder1 Codex Git Workaround

## ⚠️ UPDATE: Sandbox Fixed!
The approval policy has been changed to `auto`. Builder1 Codex can now run git commands directly! This document is kept for reference but the helper script workaround is no longer needed.

## Problem (RESOLVED)
Builder1 was running Codex with `approval_policy=never`, preventing it from executing Git commands directly. This has been fixed by updating VSCode settings.

## Solution Applied
VSCode settings updated on Builder1:
- `claude-code.approvalPolicy`: "auto" (was "never")
- `claude-code.dangerousCommands.enabled`: true
- `claude-code.git.enabled`: true

## Legacy Helper Script
A helper script at `/root/Build/scripts/git_helper.sh` is still available as a fallback.

## How Builder1 Works Now

### Codex Role (File Editing Only)
- Codex can read files, edit files, create files using its normal tools
- Codex **cannot** run Git commands
- When done editing, Codex tells the user what command to run

### User Role (Git Operations)
After Codex finishes editing files, the user executes Git operations via the helper script.

## Commands Available

```bash
# Check repository status
./scripts/git_helper.sh status

# Commit all changes
./scripts/git_helper.sh commit "Your commit message"

# Pull from remote
./scripts/git_helper.sh pull

# Push to remote
./scripts/git_helper.sh push

# All-in-one: commit + pull + push
./scripts/git_helper.sh sync "Your sync message"
```

## Example Workflow

**1. Codex makes changes:**
```
Codex: "I've updated the VNF framework tests. Files modified:
- plugins/vnf-framework/src/test/java/org/apache/cloudstack/vnf/VnfServiceImplTest.java
- plugins/vnf-framework/pom.xml

Please run: ./scripts/git_helper.sh sync 'Add VNF service unit tests'"
```

**2. User executes:**
```bash
cd /root/Build
./scripts/git_helper.sh sync 'Add VNF service unit tests'
```

**3. Output:**
```
✅ Committed: Add VNF service unit tests
✅ Pulled from origin
✅ Pushed to origin
✅ Full sync complete
```

**4. Builder2 pulls:**
```bash
cd /Builder2/Build
git pull
```

## Script Location
- **Builder1:** `/root/Build/scripts/git_helper.sh`
- **Backup:** `/tmp/builder1_git_helper.sh` (on Builder2)

## What to Tell Codex

When starting work on Builder1, paste this into the chat:

---

**Workflow Update:**

You can edit any files normally using your file tools. When you're done making changes, instead of trying to run git commands yourself (which fails due to sandbox restrictions), tell me to run:

```bash
/root/Build/scripts/git_helper.sh sync "description of changes"
```

This helper script handles commit/pull/push outside your sandbox. Just prepare the files and tell me the command to run.

Use `sync` for commit+pull+push, or use `commit`, `pull`, `push` separately if needed.

---

## Technical Details

The script wraps standard Git commands:
- `git add -A` (stage all changes)
- `git commit -m "$MESSAGE"` (commit with message)
- `git pull --rebase` (pull and rebase)
- `git push` (push to origin)

It runs in `/root/Build` directory and operates on the coordination repository at https://github.com/alexandremattioli/Build.

## Cross-Builder Sync

After Builder1 pushes changes via the helper script:

```bash
# On Builder2
cd /Builder2/Build
git pull
```

After Builder2 pushes changes:

```bash
# On Builder1 (user runs)
cd /root/Build
./scripts/git_helper.sh pull
```

## Alternative: Manual Git Commands

If the helper script fails, the user can run Git commands manually:

```bash
cd /root/Build
git add -A
git commit -m "Message"
git pull --rebase
git push
```

## Status Check

To see what's changed before committing:

```bash
./scripts/git_helper.sh status
# or manually:
git status
git diff
```

## Message Checking

Check for messages from other servers every minute:

```bash
# Read new messages
cd /root/Build
git pull
cat coordination/messages.json | jq '.messages[] | select(.to == "build1" or .to == "all") | select(.read == false)'

# Or use the automated watcher (recommended)
./scripts/watch_messages.sh &
```

The watcher script polls every 60 seconds and displays unread messages automatically.

## Troubleshooting

**"Your branch and origin/main have diverged"**
- Solution: `./scripts/git_helper.sh pull` to rebase local changes

**"Push rejected (non-fast-forward)"**
- Solution: `./scripts/git_helper.sh pull` then `./scripts/git_helper.sh push`

**"Authentication failed"**
- Check: `cat ~/.git-credentials` should contain GitHub token
- Fix: Re-run `git config --global credential.helper store` and create credentials file

**Script not executable**
- Fix: `chmod +x /root/Build/scripts/git_helper.sh`

## Security Note

Git credentials are stored in `~/.git-credentials` with token authentication. The token has been exposed in conversation logs and **MUST BE REVOKED** at https://github.com/settings/tokens. Generate a new token and update both builders:

```bash
# On each builder
echo "https://USERNAME:NEW_TOKEN@github.com" > ~/.git-credentials
```
