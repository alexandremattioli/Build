# Ubuntu 24 Generic Bootstrap

This adds a **peer-driven hive system** for Ubuntu 24.04 build nodes:
- New servers **join the hive**, say hi to all other servers, and receive messages
- Exchange ideas, capabilities, and workload through peer conversation
- Identity emerges from cluster consensus: **"Who am I? What should I become?"**
- No predefined package manifests—roles determined by hive needs

## How the Hive Works

### 1. Joining the Hive

When a new server boots:
1. **Discovers** existing hive members via UDP broadcast
2. **Says hello** to all discovered servers
3. **Asks the hive**: "Who am I? What should I become?"
4. **Listens** for advice from experienced members
5. **Achieves consensus** on role/packages/config
6. **Persists identity** and begins operating in assigned role

Existing hive members:
- **Welcome** new arrivals
- **Advise** based on current cluster state and needs
- **Share knowledge** about roles, capacity, workload

### 2. Message Exchange Protocol

The hive communicates via UDP broadcast (port 50555) with HMAC-signed messages:

| Message | Direction | Purpose |
|---------|-----------|--------|
| `HELLO` | new → all | "I've arrived, here's my hostname/IP" |
| `WELCOME` | member → new | "We see you, welcome to the hive" |
| `IDENTIFY` | new → all | "What should I become? What packages do I need?" |
| `ADVICE` | member → new | "Based on our needs, become X and install Y" |
| `STATUS` | periodic | "Here's my load, capacity, health" (future) |
| `TASK` | coordinator → worker | "Please build/test/deploy this" (future) |
| `RESULT` | worker → coordinator | "Task complete, here's the output" (future) |

### 3. Sharing the Hive Secret

All hive members must share a **common secret** for message authentication:

```bash
# On the FIRST node (founder):
sudo bash install.sh
# The installer prints the generated secret - copy it!

# On ALL subsequent nodes (before install):
sudo mkdir -p /etc/build
echo 'YOUR_SECRET_FROM_FIRST_NODE' | sudo tee /etc/build/shared_secret
sudo chmod 0600 /etc/build/shared_secret
sudo bash install.sh
```

**Why?** Only nodes with the correct secret can:
- Send authenticated messages to the hive
- Receive and validate advice from peers
- Participate in consensus and task distribution

### 4. Identity Consensus

When multiple hive members respond with advice, the new node:
1. Collects all suggestions (role, packages, config, reason)
2. Counts votes for each suggested role
3. Chooses the **most-voted role** (consensus)
4. Uses packages/config from matching advisors
5. Writes identity to `/var/lib/build/identity.json`

**Example**: If 3 advisors say "become builder" and 1 says "become runner", the node becomes a builder.

### 5. Exchanging Ideas

The hive is **collaborative**—advisors share their reasoning:

```
Advisor 1: "Become 'builder' - we only have 2, need 4 for parallel builds"
Advisor 2: "Become 'builder' - cluster has good test coverage already"
Advisor 3: "Become 'runner' - we need more test capacity"

Consensus: builder (2 votes)
Packages: openjdk-17-jdk, maven, git, build-essential
Reason: cluster needs more build capacity
```

You can extend the advisor to:
- Check current workload ("build queue is long, need builders")
- Detect resource gaps ("no GPU nodes yet, become ml-trainer")
- Balance roles ("we have 5 builders, 0 runners - become runner")
- Read external inventory (Consul, database, config files)

---

## Install (Joining the Hive)

### Option A — Cloud-init (Automated)

```yaml
#cloud-config
package_update: true
packages:
  - python3
  - arping
  - jq
  - curl
write_files:
  - path: /etc/build/shared_secret
    permissions: '0600'
    content: YOUR_HIVE_SECRET_HERE
runcmd:
  - |
    set -eux
    curl -fsSL https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24/install.sh -o /tmp/install.sh
    bash /tmp/install.sh
```

**Important**: Replace `YOUR_HIVE_SECRET_HERE` with the secret from your first node!

### Option B — Manual Install

```bash
# Step 1: Install prerequisites
sudo apt-get update
sudo apt-get install -y python3 arping jq curl

# Step 2: Set hive secret (if not first node)
sudo mkdir -p /etc/build
echo 'SECRET_FROM_FIRST_NODE' | sudo tee /etc/build/shared_secret
sudo chmod 0600 /etc/build/shared_secret

# Step 3: Install and join hive
curl -fsSL https://raw.githubusercontent.com/alexandremattioli/Build/feature/ubuntu24-bootstrap/scripts/bootstrap/ubuntu24/install.sh -o install.sh
sudo bash install.sh
```

This installs and starts:
- `build-agent.service` — Joins hive, requests identity, discovers peers
- `build-advisor.service` — Advises new arrivals on what to become

---

## Hive Commands

### See your identity
```bash
cat /var/lib/build/identity.json | jq .
```

Example output:
```json
{
  "role": "builder",
  "packages": ["openjdk-17-jdk", "maven", "git"],
  "config": {"build_slots": 4},
  "assigned_by": ["build1", "build2"],
  "assigned_at": "2025-11-08T12:34:56Z"
}
```

### See other hive members
```bash
cat /var/lib/build/peers.json | jq .
```

Example output:
```json
{
  "self": {
    "hostname": "build3",
    "primary_ip": "192.168.1.23",
    "role": "builder"
  },
  "peers": [
    {"hostname": "build1", "ip": "192.168.1.21", "role": "controller"},
    {"hostname": "build2", "ip": "192.168.1.22", "role": "builder"}
  ]
}
```

### Check network and next free IP
```bash
sudo /opt/build-agent/bootstrap.sh
```

### Claim a free IP (add as secondary)
```bash
sudo /opt/build-agent/bootstrap.sh --claim
```

### Watch hive messages in real-time
```bash
# Agent logs (joining, identity assignment)
sudo journalctl -u build-agent -f

# Advisor logs (giving advice to new nodes)
sudo journalctl -u build-advisor -f
```

### Re-ask the hive for a new identity
```bash
# Remove current identity and restart
sudo rm /var/lib/build/identity.json
sudo systemctl restart build-agent

# Watch it ask the hive again
sudo journalctl -u build-agent -f
```

### Send a message to the hive (manual test)
```bash
# Listen for broadcast messages
sudo python3 -c "
import socket, json
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('', 50555))
while True:
    data, addr = s.recvfrom(8192)
    try:
        msg = json.loads(data.decode('utf-8'))
        print(f'{addr[0]}: {msg}')
    except: pass
"
```

---

## Example: First Three Nodes Join the Hive

### Node 1: Founder (no peers, self-assigns)
```
$ sudo bash install.sh
Generated new shared secret: a3f9c8e2d1b4...
No peers found; this may be the first node (founder role).
Identity: founder

Install complete.
```

### Node 2: Joins hive, becomes controller
```
$ sudo bash install.sh
Discovered 1 peer(s)
Asking peers for role assignment...
 <- build1: become 'controller' (first node becomes controller)
Consensus: I am a 'controller'
Packages: ansible, git, build-essential

Install complete.
```

### Node 3: Joins hive, becomes builder
```
$ sudo bash install.sh
Discovered 2 peer(s)
Asking peers for role assignment...
 <- build1: become 'builder' (cluster needs builders)
 <- build2: become 'builder' (cluster needs builders)
Consensus: I am a 'builder'
Packages: openjdk-17-jdk, maven, git, build-essential

Install complete.
```

---

## Hive Architecture

### Default Role Assignment Logic

The `advisor.py` daemon suggests roles based on cluster size (customize `suggest_role()`):

| Hive Size | Suggested Role | Packages | Reason |
|-----------|----------------|----------|--------|
| 0 peers | `controller` | ansible, git | First node orchestrates |
| 1-2 peers | `builder` | openjdk, maven, git | Need build capacity |
| 3+ peers | `runner` | pytest, nodejs, npm | Have builders, need test runners |

### Extending the Hive Mind

You can make advisors smarter by checking:

**Current workload:**
```python
# Check build queue depth
if get_build_queue_length() > 10:
    return {'role': 'builder', 'reason': 'build queue is long'}
```

**Resource availability:**
```python
# Detect GPU, assign ML training role
import subprocess
if 'nvidia' in subprocess.check_output(['lspci']).decode():
    return {'role': 'ml-trainer', 'packages': ['nvidia-docker', 'cuda']}
```

**Role distribution:**
```python
# Count existing roles from peers.json
role_counts = Counter(p.get('role') for p in peers)
if role_counts.get('builder', 0) < 4:
    return {'role': 'builder', 'reason': f'only {role_counts["builder"]} builders'}
```

**External inventory:**
```python
# Query Consul for cluster state
import requests
state = requests.get('http://consul:8500/v1/kv/cluster/needs').json()
return json.loads(state[0]['Value'])
```

---

## Security

### Message Authentication
- All messages are HMAC-SHA256 signed with the shared secret
- Invalid signatures are silently rejected
- Broadcast is **local subnet only** (doesn't cross routers by default)

### Shared Secret Distribution

**Manual method** (small clusters):
```bash
# On first node:
cat /etc/build/shared_secret
# Copy output to other nodes before install
```

**Automated method** (cloud-init, Ansible, etc.):
```yaml
# In cloud-init or provisioning template:
write_files:
  - path: /etc/build/shared_secret
    permissions: '0600'
    content: '{{ hive_secret_from_vault }}'
```

**Rotation** (change secret on all nodes):
```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 16)

# Deploy to all nodes (Ansible example):
ansible all -b -m copy -a "content=$NEW_SECRET dest=/etc/build/shared_secret mode=0600"
ansible all -b -m systemd -a "name=build-agent state=restarted"
```

### Cross-Subnet Hives

Broadcast only works on a single subnet. For multi-subnet hives:

1. **Use multicast** (if your network supports it):
   - Change `sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)` to multicast
   - Use a multicast group like `239.255.0.1`

2. **Add a coordinator** (recommended for production):
   - Run a lightweight HTTP service that nodes register with
   - Nodes POST to `/hive/join` and GET `/hive/peers`
   - Can use Redis, Consul, etcd, or a simple Flask app

3. **VPN overlay** (Tailscale, WireGuard):
   - All nodes on same virtual subnet
   - Broadcast works across physical networks

---

## Next Steps: Building Hive Intelligence

### 1. Implement Package Installation
After identity is assigned, automatically install packages:
```python
# In peer_agent.py, after identity is written:
if identity and identity.get('packages'):
    subprocess.run(['apt-get', 'install', '-y'] + identity['packages'])
```

### 2. Add Heartbeat Messages
Periodic STATUS broadcasts to detect departed members:
```python
# Every 30 seconds:
broadcast({'kind': 'STATUS', 'load': os.getloadavg(), 'uptime': ...})
```

### 3. Task Distribution
Controller sends TASK messages, workers respond with RESULT:
```python
# Controller:
broadcast({'kind': 'TASK', 'id': uuid(), 'command': 'mvn test', 'repo': 'https://...'})

# Worker:
result = run_task(task['command'])
send_to(controller_ip, {'kind': 'RESULT', 'task_id': task['id'], 'output': result})
```

### 4. Role Migration
Allow nodes to change roles based on hive evolution:
```python
# Check if role is still needed every hour
if current_role == 'builder' and hive_has_enough_builders():
    remove_identity()
    request_new_role()
```

### 5. Capability Exchange
Nodes share what they can do (beyond just role):
```python
payload['capabilities'] = {
    'cpu_cores': os.cpu_count(),
    'ram_gb': get_total_ram(),
    'has_gpu': detect_gpu(),
    'docker_installed': shutil.which('docker') is not None,
    'languages': ['java', 'python', 'go']
}
```

---

## Troubleshooting the Hive

### No peers discovered
**Symptom:** `Discovered 0 peer(s)`

**Fixes:**
```bash
# Check firewall
sudo ufw allow 50555/udp
sudo ufw status

# Verify network interface is up
ip -br addr

# Test broadcast manually
echo 'test' | nc -u -b 192.168.1.255 50555

# Check if other nodes are listening
sudo netstat -ulnp | grep 50555
```

### No advice received
**Symptom:** `No advice received from peers`

**Fixes:**
```bash
# Ensure advisor service is running on at least one peer
sudo systemctl status build-advisor
sudo journalctl -u build-advisor -n 50

# Check shared secret matches
sudo cat /etc/build/shared_secret  # compare across nodes

# Verify HMAC signatures (mismatched = silent reject)
# Force secret sync, then restart
sudo systemctl restart build-agent build-advisor
```

### Identity stuck as unassigned
**Symptom:** `identity.json` missing or empty

**Fix:**
```bash
# Force re-discovery
sudo rm -f /var/lib/build/identity.json
sudo systemctl restart build-agent
sudo journalctl -u build-agent -f

# If still fails, check advisor logs on peers
ssh build1 'sudo journalctl -u build-advisor -f'
```

### Messages not reaching all nodes
**Symptom:** Some nodes see HELLO, others don't

**Causes:**
- Network switch blocking broadcast (check switch config)
- Different subnets (broadcast doesn't cross routers)
- Firewall on specific nodes

**Fix:**
```bash
# Test broadcast reach from each node
for node in build1 build2 build3; do
  ssh $node "echo 'ping' | nc -u -b 192.168.1.255 50555"
done

# Should see messages on all nodes listening on port 50555
```

---

## Hive Philosophy

> **"The hive is smarter than any individual node."**

Instead of:
- ❌ Predefined server configs
- ❌ Manual role assignment
- ❌ Static package lists
- ❌ Centralized orchestration

The hive uses:
- ✅ **Peer consensus** on roles
- ✅ **Dynamic adaptation** to cluster needs
- ✅ **Distributed decision-making**
- ✅ **Emergent behavior** from simple rules

Each node asks: **"What does the hive need from me?"**  
The hive answers: **"We need you to be X because Y."**

This creates a **self-organizing, self-healing build cluster** that adapts to workload, failures, and growth without manual intervention.
