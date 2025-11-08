# Ubuntu 24 Generic Bootstrap

This adds a **peer-driven role assignment** system for Ubuntu 24.04 build nodes:
- New servers ask existing peers: **"Who am I? What should I become?"**
- Existing nodes advise based on cluster state (controller, builder, runner, etc.)
- Consensus determines role and package list
- No predefined package manifests—identity emerges from cluster needs

## Architecture

1. **Discovery phase**: New node broadcasts HELLO, collects peer list
2. **Identity phase**: Sends IDENTIFY request, receives ADVICE responses
3. **Consensus**: Chooses most-voted role, persists identity
4. **Configuration**: (future) Install packages, apply config based on assigned role

## Install (on an Ubuntu 24 node)

### Option A — Cloud-init
```yaml
#cloud-config
package_update: true
packages:
  - python3
  - arping
  - jq
  - curl
runcmd:
  - |
    set -eux
    curl -fsSL https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24/install.sh -o /tmp/install.sh
    bash /tmp/install.sh
```

### Option B — Manual install
```bash
sudo apt-get update
sudo apt-get install -y python3 arping jq curl
curl -fsSL https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24/install.sh -o install.sh
sudo bash install.sh
```

This sets up:
- `build-agent.service`: peer discovery + identity assignment
- `build-advisor.service`: (optional) advisor daemon to respond to IDENTIFY requests

## Commands

### Check network and identity
```bash
sudo /opt/build-agent/bootstrap.sh
cat /var/lib/build/identity.json | jq .
```

### View discovered peers
```bash
cat /var/lib/build/peers.json | jq .
```

### Claim next free IP
```bash
sudo /opt/build-agent/bootstrap.sh --claim
```

### Follow logs
```bash
sudo journalctl -u build-agent -f
sudo journalctl -u build-advisor -f
```

### Restart identity discovery (re-ask peers)
```bash
sudo rm /var/lib/build/identity.json
sudo systemctl restart build-agent
```

## Identity Structure

`/var/lib/build/identity.json`:
```json
{
  "role": "builder",
  "packages": ["openjdk-17-jdk", "maven", "git"],
  "config": {"build_slots": 4},
  "assigned_by": ["build1", "build2"],
  "assigned_at": "2025-11-08T12:34:56Z"
}
```

## Role Assignment Logic

The `advisor.py` daemon suggests roles based on cluster size (customize `suggest_role()` for your needs):
- **0 peers** → `controller` (first node, orchestration)
- **1-2 peers** → `builder` (compile jobs)
- **3+ peers** → `runner` (test execution)

You can extend this with:
- Resource detection (CPU/RAM/disk)
- Existing role distribution ("we have 5 builders, need runners")
- Capability negotiation (GPU presence, storage capacity)
- External inventory (Consul, etcd)

## Security

- UDP broadcast uses HMAC-SHA256 if `/etc/build/shared_secret` exists
- Installer generates a random secret on first run
- **Important**: Copy the same secret to all trusted nodes:
  ```bash
  # On first node:
  cat /etc/build/shared_secret
  # On subsequent nodes (before install):
  sudo mkdir -p /etc/build
  echo '<secret from first node>' | sudo tee /etc/build/shared_secret
  sudo chmod 0600 /etc/build/shared_secret
  ```
- Broadcast is local-subnet only (cross-subnet needs a coordinator)

## Protocol Messages

| Kind | Direction | Purpose |
|------|-----------|--------|
| `HELLO` | new → all | Announce presence |
| `WELCOME` | peer → new | Acknowledge peer |
| `IDENTIFY` | new → all | Request role assignment |
| `ADVICE` | peer → new | Suggest role/packages/config |

## Next Steps

- **Implement package installation**: After identity is assigned, run `apt-get install` for the package list
- **Config application**: Apply role-specific config (e.g., systemd units, cron jobs)
- **Heartbeat/health**: Periodic re-discovery to detect cluster changes
- **Cross-subnet coordinator**: HTTP registry or mDNS for multi-subnet clusters
- **Role migration**: Allow nodes to change roles based on cluster evolution

## Example: First Boot Sequence

```
# Node 1 (founder)
> No peers found; this may be the first node (founder role).
> Identity: founder

# Node 2 (joins cluster)
> Discovered 1 peer(s)
> Asking peers for role assignment...
>  <- build1: become 'controller' (first node becomes controller)
> Consensus: I am a 'controller'
> Packages: ansible, git, build-essential

# Node 3 (joins cluster)
> Discovered 2 peer(s)
> Asking peers for role assignment...
>  <- build1: become 'builder' (cluster needs builders)
>  <- build2: become 'builder' (cluster needs builders)
> Consensus: I am a 'builder'
> Packages: openjdk-17-jdk, maven, git, build-essential
```

## Troubleshooting

**No peers discovered**
- Check firewall: `sudo ufw allow 50555/udp`
- Verify broadcast works: `ip -br addr` (ensure interface is up)
- Check shared secret matches on all nodes

**No advice received**
- Ensure at least one peer is running `build-advisor.service`
- Check advisor logs: `sudo journalctl -u build-advisor -f`
- Verify HMAC signature (mismatched secrets are rejected silently)

**Identity stuck as unassigned**
- Force re-discovery: `sudo rm /var/lib/build/identity.json && sudo systemctl restart build-agent`
