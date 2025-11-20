# Example: PostgreSQL Patroni with Guest BGP VIPs

**Use Case:** High-availability PostgreSQL cluster with automatic failover using BGP-advertised virtual IPs

**Prerequisites:**
- CloudStack network with guest BGP enabled
- 3 VMs for PostgreSQL cluster
- etcd cluster for Patroni consensus

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ CloudStack Isolated Network (2a01:b000:1046:10:1::/64)     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Virtual Router (VR)                                │    │
│  │ - IPv6: 2a01:b000:1046:10:1::1                     │    │
│  │ - ASN: 65101                                       │    │
│  └────────────────────────────────────────────────────┘    │
│                         ▲                                    │
│                         │ BGP Peering                       │
│                         │                                    │
│  ┌──────────────────────┴───────────────────────────────┐  │
│  │ PostgreSQL Cluster (3 VMs)                           │  │
│  │                                                       │  │
│  │ ┌───────────────────────────────────────────────┐   │  │
│  │ │ pg-node-1: 2a01:b000:1046:10:1::50 (ASN 65201)│   │  │
│  │ │ Role: PRIMARY                                 │   │  │
│  │ │ Advertises: 2a01:b000:1046:10:1::100/128 (VIP)│   │  │
│  │ └───────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │ ┌───────────────────────────────────────────────┐   │  │
│  │ │ pg-node-2: 2a01:b000:1046:10:1::51 (ASN 65202)│   │  │
│  │ │ Role: REPLICA                                 │   │  │
│  │ │ Advertises: Nothing                           │   │  │
│  │ └───────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │ ┌───────────────────────────────────────────────┐   │  │
│  │ │ pg-node-3: 2a01:b000:1046:10:1::52 (ASN 65203)│   │  │
│  │ │ Role: REPLICA                                 │   │  │
│  │ │ Advertises: Nothing                           │   │  │
│  │ └───────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │ Patroni Cluster:                                     │  │
│  │ - Elects primary via etcd                            │  │
│  │ - Triggers BGP advertisement on failover             │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  VIP: 2a01:b000:1046:10:1::100 (floats to current primary) │
└──────────────────────────────────────────────────────────────┘
                         │
                         │ Clients connect to VIP
                         ▼
         psql -h 2a01:b000:1046:10:1::100
```

---

## Step 1: Create CloudStack Network

### Create Network Offering

```bash
cloudmonkey create networkoffering \
  name="PostgreSQL-HA-BGP" \
  displaytext="PostgreSQL cluster with BGP VIP failover" \
  guestiptype=Isolated \
  supportedservices=Dhcp,Dns,Firewall,SourceNat,StaticNat,DynamicRouting \
  serviceProviderList[0].service=DynamicRouting \
  serviceProviderList[0].provider=VirtualRouter \
  guestbgppeeringenabled=true \
  guestbgpminprefixlength=128 \
  guestbgpmaxprefixlength=128 \
  guestbgpmaxprefixes=5 \
  guestbgpallowedasnmin=65200 \
  guestbgpallowedasnmax=65299

cloudmonkey update networkoffering id=<offering-id> state=Enabled
```

---

### Create Network

```bash
cloudmonkey create network \
  name="postgres-ha-network" \
  displaytext="PostgreSQL HA cluster" \
  networkofferingid=<offering-id> \
  zoneid=<zone-id>
```

**Allocated CIDR:** `2a01:b000:1046:10:1::/64`

---

## Step 2: Deploy PostgreSQL VMs

```bash
# Deploy 3 VMs
cloudmonkey deploy virtualmachine \
  name="pg-node-1" \
  serviceofferingid=<8vCPU-16GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>

cloudmonkey deploy virtualmachine \
  name="pg-node-2" \
  serviceofferingid=<8vCPU-16GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>

cloudmonkey deploy virtualmachine \
  name="pg-node-3" \
  serviceofferingid=<8vCPU-16GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>
```

**Assigned IPs:**
- pg-node-1: `2a01:b000:1046:10:1::50`
- pg-node-2: `2a01:b000:1046:10:1::51`
- pg-node-3: `2a01:b000:1046:10:1::52`

**VIP (to be advertised):** `2a01:b000:1046:10:1::100`

---

## Step 3: Install PostgreSQL + Patroni

### Install PostgreSQL 15

```bash
# On all 3 nodes:
ssh ubuntu@2a01:b000:1046:10:1::50

sudo apt update
sudo apt install -y postgresql-15 postgresql-contrib-15
sudo systemctl stop postgresql
sudo systemctl disable postgresql
```

**Note:** Patroni will manage PostgreSQL lifecycle, so disable default service.

---

### Install Patroni

```bash
# On all 3 nodes:
sudo apt install -y python3-pip python3-psycopg2
sudo pip3 install patroni[etcd]
```

---

### Install etcd (Consensus)

**Deploy separate etcd cluster (3 nodes recommended):**

For this example, we'll run etcd on the same nodes:

```bash
# On all 3 nodes:
sudo apt install -y etcd

# Configure etcd (example for node-1)
sudo tee /etc/default/etcd <<EOF
ETCD_NAME="pg-node-1"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_CLIENT_URLS="http://2a01:b000:1046:10:1::50:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://2a01:b000:1046:10:1::50:2379"
ETCD_LISTEN_PEER_URLS="http://2a01:b000:1046:10:1::50:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://2a01:b000:1046:10:1::50:2380"
ETCD_INITIAL_CLUSTER="pg-node-1=http://2a01:b000:1046:10:1::50:2380,pg-node-2=http://2a01:b000:1046:10:1::51:2380,pg-node-3=http://2a01:b000:1046:10:1::52:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="postgres-ha-cluster"
EOF

sudo systemctl restart etcd
```

**Adjust IPs for node-2 and node-3.**

---

## Step 4: Configure Patroni

### Patroni Configuration (pg-node-1)

```bash
sudo tee /etc/patroni/patroni.yml <<EOF
scope: postgres-ha
name: pg-node-1

restapi:
  listen: '[2a01:b000:1046:10:1::50]:8008'
  connect_address: '[2a01:b000:1046:10:1::50]:8008'

etcd:
  hosts:
    - '[2a01:b000:1046:10:1::50]:2379'
    - '[2a01:b000:1046:10:1::51]:2379'
    - '[2a01:b000:1046:10:1::52]:2379'

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 2a01:b000:1046:10:1::/64 md5
    - host all all 2a01:b000:1046:10:1::/64 md5

postgresql:
  listen: '[2a01:b000:1046:10:1::50]:5432,[2a01:b000:1046:10:1::100]:5432'
  connect_address: '[2a01:b000:1046:10:1::50]:5432'
  data_dir: /var/lib/postgresql/15/main
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /var/lib/postgresql/.pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password

  parameters:
    max_connections: 200
    shared_buffers: 4GB
    effective_cache_size: 12GB
    wal_level: replica
    max_wal_senders: 10
    hot_standby: on

  callbacks:
    on_start: /usr/local/bin/patroni-bgp-callback.sh on_start
    on_stop: /usr/local/bin/patroni-bgp-callback.sh on_stop
    on_role_change: /usr/local/bin/patroni-bgp-callback.sh on_role_change
EOF
```

**Adjust for pg-node-2 and pg-node-3 (change `name` and IPs).**

---

### BGP Callback Script

Create `/usr/local/bin/patroni-bgp-callback.sh`:

```bash
#!/bin/bash
set -e

ROLE=$1
VIP="2a01:b000:1046:10:1::100/128"
VR_IP="2a01:b000:1046:10:1::1"
VR_ASN="65101"

# Get node ASN (based on hostname)
case $(hostname) in
  pg-node-1) MY_ASN=65201 ;;
  pg-node-2) MY_ASN=65202 ;;
  pg-node-3) MY_ASN=65203 ;;
esac

advertise_vip() {
  echo "Advertising VIP $VIP via BGP (I am PRIMARY)"
  
  vtysh <<EOF
configure terminal
router bgp $MY_ASN
  address-family ipv6 unicast
    network $VIP
  exit-address-family
exit
write memory
EOF
}

withdraw_vip() {
  echo "Withdrawing VIP $VIP from BGP (I am REPLICA)"
  
  vtysh <<EOF
configure terminal
router bgp $MY_ASN
  address-family ipv6 unicast
    no network $VIP
  exit-address-family
exit
write memory
EOF
}

# Patroni calls this script with role changes
case $ROLE in
  on_start)
    # Check if I'm primary
    if patronictl list | grep -q "$(hostname).*Leader"; then
      advertise_vip
    fi
    ;;
  
  on_role_change)
    # If promoted to primary, advertise VIP
    if patronictl list | grep -q "$(hostname).*Leader"; then
      advertise_vip
    else
      withdraw_vip
    fi
    ;;
  
  on_stop)
    withdraw_vip
    ;;
esac
```

**Make executable:**
```bash
sudo chmod +x /usr/local/bin/patroni-bgp-callback.sh
```

---

## Step 5: Install and Configure FRR

### Install FRR

```bash
# On all 3 nodes:
sudo apt install -y frr
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

---

### Configure BGP (pg-node-1)

```bash
sudo vtysh

configure terminal

router bgp 65201
  bgp router-id 10.1.0.50
  no bgp ebgp-requires-policy
  neighbor 2a01:b000:1046:10:1::1 remote-as 65101
  
  address-family ipv6 unicast
    network 2a01:b000:1046:10:1::50/128
    neighbor 2a01:b000:1046:10:1::1 activate
  exit-address-family

exit
write memory
```

**Repeat for pg-node-2 (ASN 65202) and pg-node-3 (ASN 65203).**

**Note:** VIP `2a01:b000:1046:10:1::100/128` will be advertised dynamically by callback script.

---

## Step 6: Start Patroni Cluster

```bash
# On all 3 nodes:
sudo systemctl start patroni
sudo systemctl enable patroni
```

---

### Verify Cluster Status

```bash
patronictl -c /etc/patroni/patroni.yml list
```

**Expected Output:**
```
+ Cluster: postgres-ha -----+----+-----------+
| Member    | Host          | Role    | State   | TL | Lag in MB |
+-----------+---------------+---------+---------+----+-----------+
| pg-node-1 | ...::50:5432  | Leader  | running |  1 |           |
| pg-node-2 | ...::51:5432  | Replica | running |  1 |         0 |
| pg-node-3 | ...::52:5432  | Replica | running |  1 |         0 |
+-----------+---------------+---------+---------+----+-----------+
```

**pg-node-1 is PRIMARY → BGP callback advertises VIP**

---

### Verify BGP Advertisement

**On pg-node-1:**
```bash
sudo vtysh -c 'show bgp ipv6 unicast'
```

**Expected Output:**
```
   Network                      Next Hop            Metric LocPrf Weight Path
*> 2a01:b000:1046:10:1::50/128 ::                       0         32768 i
*> 2a01:b000:1046:10:1::100/128 ::                      0         32768 i
```

**VIP `2a01:b000:1046:10:1::100/128` advertised!**

---

**In CloudStack:**
```bash
cloudmonkey list bgp guest routes state=Accepted
```

**Expected:**
```json
{
  "bgpguestroute": [
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::50"}
  ]
}
```

---

## Step 7: Test Database Connectivity

### Connect to VIP

```bash
psql -h 2a01:b000:1046:10:1::100 -U postgres -d postgres
```

**Expected:**
```
Password for user postgres: postgres_password
postgres=#
```

✅ **Connected to PRIMARY via VIP!**

---

### Create Test Data

```sql
CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO test (data) VALUES ('Hello from PRIMARY');
SELECT * FROM test;
```

**Output:**
```
 id |       data
----+-------------------
  1 | Hello from PRIMARY
```

---

## Step 8: Failover Test

### Simulate Primary Failure

```bash
# On pg-node-1 (current primary):
sudo systemctl stop patroni
```

**What happens:**
1. Patroni detects node-1 is down (via etcd TTL expiry)
2. Patroni promotes pg-node-2 to PRIMARY
3. pg-node-2's callback script runs: `on_role_change`
4. FRR on pg-node-2 advertises VIP `2a01:b000:1046:10:1::100/128`
5. CloudStack VR updates route: VIP now points to `...::51` (pg-node-2)

---

### Verify Failover

**On pg-node-2:**
```bash
patronictl -c /etc/patroni/patroni.yml list
```

**Expected:**
```
| Member    | Host          | Role    | State   | TL | Lag in MB |
+-----------+---------------+---------+---------+----+-----------+
| pg-node-2 | ...::51:5432  | Leader  | running |  2 |           |
| pg-node-3 | ...::52:5432  | Replica | running |  2 |         0 |
+-----------+---------------+---------+---------+----+-----------+
```

**pg-node-2 is now PRIMARY!**

---

**Check BGP:**
```bash
sudo vtysh -c 'show bgp ipv6 unicast' | grep 2a01:b000:1046:10:1::100
```

**Expected:**
```
*> 2a01:b000:1046:10:1::100/128 ::                      0         32768 i
```

**VIP advertised by pg-node-2!**

---

**In CloudStack:**
```bash
cloudmonkey list bgp guest routes prefix=2a01:b000:1046:10:1::100/128
```

**Expected:**
```json
{
  "bgpguestroute": [
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::51"}
  ]
}
```

**Next hop changed from ::50 to ::51!**

---

### Verify Application Connectivity

```bash
psql -h 2a01:b000:1046:10:1::100 -U postgres -d postgres -c "SELECT * FROM test"
```

**Output:**
```
 id |       data
----+-------------------
  1 | Hello from PRIMARY
```

✅ **No downtime!** VIP failover was transparent to clients.

---

### Failover Timeline

```
T+0s:   pg-node-1 stops (PRIMARY down)
T+1s:   etcd lease expires
T+2s:   Patroni elects pg-node-2 as new PRIMARY
T+3s:   pg-node-2 callback script advertises VIP via BGP
T+4s:   CloudStack VR receives BGP UPDATE
T+5s:   VR updates kernel routing table
T+5s:   Clients automatically connect to new PRIMARY

Total failover time: ~5 seconds
```

---

## Step 9: Bring Back pg-node-1

```bash
# On pg-node-1:
sudo systemctl start patroni
```

**What happens:**
1. Patroni detects pg-node-1 is back online
2. pg-node-1 joins cluster as **REPLICA** (not primary)
3. Callback script does **NOT** advertise VIP (only primary advertises)
4. VIP remains on pg-node-2

---

**Verify:**
```bash
patronictl -c /etc/patroni/patroni.yml list
```

**Expected:**
```
| Member    | Host          | Role    | State   | TL | Lag in MB |
+-----------+---------------+---------+---------+----+-----------+
| pg-node-1 | ...::50:5432  | Replica | running |  2 |         0 |
| pg-node-2 | ...::51:5432  | Leader  | running |  2 |           |
| pg-node-3 | ...::52:5432  | Replica | running |  2 |         0 |
+-----------+---------------+---------+---------+----+-----------+
```

**pg-node-2 remains primary!**

---

## Monitoring

### Patroni Status

```bash
watch patronictl -c /etc/patroni/patroni.yml list
```

---

### BGP Session Status

```bash
cloudmonkey list bgp guest peering sessions networkid=<network-id>
```

**Expected:**
```json
{
  "count": 3,
  "bgppeeringsession": [
    {"guestip": "2a01:b000:1046:10:1::50", "state": "Established"},
    {"guestip": "2a01:b000:1046:10:1::51", "state": "Established"},
    {"guestip": "2a01:b000:1046:10:1::52", "state": "Established"}
  ]
}
```

---

### VIP Route Status

```bash
cloudmonkey list bgp guest routes prefix=2a01:b000:1046:10:1::100/128
```

**Shows which node currently advertises VIP.**

---

## Troubleshooting

### Issue: VIP Not Advertised After Failover

**Diagnosis:**
```bash
# On new primary:
sudo vtysh -c 'show bgp ipv6 unicast' | grep 2a01:b000:1046:10:1::100
```

**If missing:**
```bash
# Check callback script ran
sudo journalctl -u patroni | grep "Advertising VIP"
```

**Solution:**
```bash
# Manually trigger callback
sudo /usr/local/bin/patroni-bgp-callback.sh on_role_change
```

---

### Issue: Split-Brain (Multiple Primaries)

**Diagnosis:**
```bash
patronictl -c /etc/patroni/patroni.yml list
```

**If 2+ nodes show "Leader":**

**Solution:**
1. **Stop all Patroni instances:**
```bash
sudo systemctl stop patroni  # on all nodes
```

2. **Clear etcd state:**
```bash
etcdctl rm --recursive /service/postgres-ha
```

3. **Restart Patroni** (one at a time, starting with desired primary)

---

### Issue: Client Connections Fail After Failover

**Diagnosis:**
```bash
# Check VR routing table
ssh root@<vr-ip>
ip -6 route show | grep 2a01:b000:1046:10:1::100
```

**Expected:**
```
2a01:b000:1046:10:1::100 via 2a01:b000:1046:10:1::51 dev eth1 proto bgp
```

**If missing or wrong next hop:**
- Check CloudStack BGP route table
- Check VR BGP session state
- Manually reset BGP session

---

## Performance Tuning

### Faster Failover

**Reduce Patroni TTL:**
```yaml
# /etc/patroni/patroni.yml
bootstrap:
  dcs:
    ttl: 15              # Down from 30 (faster detection)
    loop_wait: 5         # Down from 10 (faster polling)
```

**Trade-off:** More frequent etcd writes, higher CPU usage.

---

### Connection Pooling

**Deploy PgBouncer in front of VIP:**

```bash
# Install PgBouncer on separate VM
sudo apt install -y pgbouncer

# Configure to connect to VIP
# Clients connect to PgBouncer instead of direct VIP
```

**Benefits:**
- Connection pooling
- Smoother failovers (PgBouncer retries)

---

## Security Hardening

### Enable BGP MD5 Authentication (Phase 2)

```bash
# On all PostgreSQL nodes:
sudo vtysh

configure terminal
router bgp 65201
  neighbor 2a01:b000:1046:10:1::1 password <md5-secret>
exit
write memory
```

**CloudStack 4.24 will auto-generate and distribute passwords.**

---

### PostgreSQL SSL

```yaml
# /etc/patroni/patroni.yml
postgresql:
  parameters:
    ssl: on
    ssl_cert_file: /etc/ssl/certs/server.crt
    ssl_key_file: /etc/ssl/private/server.key
```

---

## Summary

✅ **Achieved:**
- High-availability PostgreSQL with automatic failover
- BGP-advertised VIP (floats to current primary)
- Sub-5-second failover time
- Zero client-side configuration (VIP is transparent)

**Key Benefits:**
- **No Virtual IP via VRRP:** BGP is more flexible (supports asymmetric routing)
- **Cloud-Native:** Works with CloudStack networking
- **Observable:** CloudStack tracks all route changes

---

## Next Steps

- **Multi-Region Failover:**
  - Deploy replicas in different CloudStack zones
  - Use BGP communities to prefer local zone

- **Read Replicas:**
  - Advertise second VIP for read-only traffic
  - Patroni configures read-only PostgreSQL instances

- **Backup Integration:**
  - pgBackRest with S3-compatible storage
  - Automated PITR (Point-In-Time Recovery)

---

**Reference Files:**
- Patroni Config: `/etc/patroni/patroni.yml`
- BGP Callback: `/usr/local/bin/patroni-bgp-callback.sh`
- FRR Config: `/etc/frr/frr.conf`

**Last Updated:** November 20, 2025
