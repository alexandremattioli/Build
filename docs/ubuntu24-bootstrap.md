# Ubuntu 24 Generic Bootstrap

This adds a minimal bootstrap for Ubuntu 24.04 nodes so they can:
- Detect their primary interface and IP/CIDR
- Scan the subnet for the next free IP (without claiming it by default)
- Discover and greet other build servers on the LAN via UDP broadcast
- Persist discovered peers at `/var/lib/build/peers.json`

## Install (on an Ubuntu 24 node)

Option A — One-liner (cloud-init)
```
# Use this as cloud-init user-data, or run these packages then the install script
```

Option B — Manual install
```
sudo apt-get update
sudo apt-get install -y python3 arping jq curl
curl -fsSL https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24/install.sh -o install.sh
sudo bash install.sh
```

This sets up a systemd service `build-agent.service` that runs the peer discovery agent.

## Commands

Check interface, current IP, and next free IP (without claiming it):
```
sudo /opt/build-agent/bootstrap.sh
```

Claim the next free IP as a secondary address:
```
sudo /opt/build-agent/bootstrap.sh --claim
```

View discovered peers:
```
cat /var/lib/build/peers.json | jq .
```

Follow logs:
```
sudo journalctl -u build-agent -f
```

## Security
- UDP broadcast uses an optional HMAC signature if `/etc/build/shared_secret` exists. The installer creates a random secret by default. Copy the same secret to all authorized build servers.
- Broadcast runs only on the local subnet. Adjust the agent to use multicast or a coordinator if needed across subnets.

## Next steps
- Integrate a coordinator for cross-subnet discovery (e.g., lightweight HTTP registry or Consul).
- Implement advice/coordination messages beyond HELLO/WELCOME (e.g., roles, capabilities, tasks).
- Extend to configure package prerequisites per role (cloudstack builders, test runners, etc.).
