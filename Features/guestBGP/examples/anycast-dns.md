# Example: Anycast DNS with Guest BGP

**Use Case:** Highly-available DNS service using anycast (same IP advertised from multiple servers)

**Prerequisites:**
- CloudStack network with guest BGP enabled
- 3 VMs for DNS servers
- BIND9 or PowerDNS

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
│  │ DNS Servers (3 VMs) - All advertise SAME IP!        │  │
│  │                                                       │  │
│  │ ┌───────────────────────────────────────────────┐   │  │
│  │ │ dns-1: 2a01:b000:1046:10:1::50 (ASN 65201)    │   │  │
│  │ │ Anycast IP: 2a01:b000:1046:10:1::100/128      │   │  │
│  │ │ Advertises: 2a01:b000:1046:10:1::100/128      │   │  │
│  │ └───────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │ ┌───────────────────────────────────────────────┐   │  │
│  │ │ dns-2: 2a01:b000:1046:10:1::51 (ASN 65202)    │   │  │
│  │ │ Anycast IP: 2a01:b000:1046:10:1::100/128      │   │  │
│  │ │ Advertises: 2a01:b000:1046:10:1::100/128      │   │  │
│  │ └───────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │ ┌───────────────────────────────────────────────┐   │  │
│  │ │ dns-3: 2a01:b000:1046:10:1::52 (ASN 65203)    │   │  │
│  │ │ Anycast IP: 2a01:b000:1046:10:1::100/128      │   │  │
│  │ │ Advertises: 2a01:b000:1046:10:1::100/128      │   │  │
│  │ └───────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │ VR receives 3 routes for 2a01:b000:1046:10:1::100   │  │
│  │ Uses ECMP (Equal-Cost Multi-Path) routing          │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                         │
                         │ Clients use anycast IP
                         ▼
       dig @2a01:b000:1046:10:1::100 example.com
       (Automatically routed to nearest DNS server)
```

---

## Anycast Concept

**Traditional Unicast:**
- Each server has unique IP
- Clients must know which IP to use
- Failover requires DNS updates or load balancer

**Anycast:**
- Multiple servers share **same IP address**
- Routing protocol (BGP) selects closest/best server
- Automatic failover (if one server fails, BGP routes to others)

**Benefits:**
- **High Availability:** No single point of failure
- **Load Distribution:** Traffic spreads across servers
- **Low Latency:** Clients connect to nearest server

---

## Step 1: Create CloudStack Network

```bash
cloudmonkey create networkoffering \
  name="Anycast-DNS-BGP" \
  displaytext="Anycast DNS with BGP load balancing" \
  guestiptype=Isolated \
  supportedservices=Dhcp,Dns,Firewall,SourceNat,DynamicRouting \
  serviceProviderList[0].service=DynamicRouting \
  serviceProviderList[0].provider=VirtualRouter \
  guestbgppeeringenabled=true \
  guestbgpminprefixlength=128 \
  guestbgpmaxprefixlength=128 \
  guestbgpmaxprefixes=5 \
  guestbgpallowedasnmin=65200 \
  guestbgpallowedasnmax=65299

cloudmonkey update networkoffering id=<offering-id> state=Enabled

cloudmonkey create network \
  name="anycast-dns-network" \
  displaytext="Anycast DNS cluster" \
  networkofferingid=<offering-id> \
  zoneid=<zone-id>
```

---

## Step 2: Deploy DNS VMs

```bash
cloudmonkey deploy virtualmachine \
  name="dns-1" \
  serviceofferingid=<2vCPU-4GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>

cloudmonkey deploy virtualmachine \
  name="dns-2" \
  serviceofferingid=<2vCPU-4GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>

cloudmonkey deploy virtualmachine \
  name="dns-3" \
  serviceofferingid=<2vCPU-4GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>
```

**Assigned IPs:**
- dns-1: `2a01:b000:1046:10:1::50`
- dns-2: `2a01:b000:1046:10:1::51`
- dns-3: `2a01:b000:1046:10:1::52`

**Anycast IP (shared):** `2a01:b000:1046:10:1::100`

---

## Step 3: Install BIND9

```bash
# On all 3 VMs:
ssh ubuntu@2a01:b000:1046:10:1::50

sudo apt update
sudo apt install -y bind9 bind9utils
```

---

### Configure BIND9

**Edit `/etc/bind/named.conf.options`:**

```bash
sudo tee /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";
    
    // Listen on anycast IP + node IP
    listen-on-v6 { 2a01:b000:1046:10:1::100; 2a01:b000:1046:10:1::50; };
    
    // Allow queries from network
    allow-query { 2a01:b000:1046:10:1::/64; any; };
    
    // Disable recursion (authoritative DNS only)
    recursion no;
    
    dnssec-validation auto;
};
EOF
```

**Adjust node IP for dns-2 and dns-3.**

---

### Create DNS Zone

**Edit `/etc/bind/named.conf.local`:**

```bash
sudo tee -a /etc/bind/named.conf.local <<EOF
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com";
};
EOF
```

---

**Create zone file `/etc/bind/zones/db.example.com`:**

```bash
sudo mkdir /etc/bind/zones
sudo tee /etc/bind/zones/db.example.com <<EOF
\$TTL 300
@       IN      SOA     ns1.example.com. admin.example.com. (
                        2025112001 ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Minimum TTL

; Name servers
@       IN      NS      ns1.example.com.
@       IN      NS      ns2.example.com.
@       IN      NS      ns3.example.com.

; Anycast IP for all name servers
ns1     IN      AAAA    2a01:b000:1046:10:1::100
ns2     IN      AAAA    2a01:b000:1046:10:1::100
ns3     IN      AAAA    2a01:b000:1046:10:1::100

; Example records
www     IN      AAAA    2001:db8::1
mail    IN      AAAA    2001:db8::2
EOF
```

**Note:** All 3 name servers use **same anycast IP** `2a01:b000:1046:10:1::100`.

---

**Restart BIND9:**
```bash
sudo systemctl restart bind9
sudo systemctl enable bind9
```

---

## Step 4: Add Anycast IP to Loopback Interface

```bash
# On all 3 VMs:
sudo ip -6 addr add 2a01:b000:1046:10:1::100/128 dev lo
```

**Make persistent (add to `/etc/network/interfaces`):**

```bash
sudo tee -a /etc/network/interfaces <<EOF
# Anycast IP on loopback
iface lo inet6 static
    address 2a01:b000:1046:10:1::100/128
EOF
```

---

**Verify:**
```bash
ip -6 addr show lo | grep 2a01:b000:1046:10:1::100
```

**Expected:**
```
inet6 2a01:b000:1046:10:1::100/128 scope global
```

---

## Step 5: Install and Configure FRR

### Install FRR

```bash
# On all 3 VMs:
sudo apt install -y frr
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

---

### Configure BGP (dns-1)

```bash
sudo vtysh

configure terminal

router bgp 65201
  bgp router-id 10.1.0.50
  no bgp ebgp-requires-policy
  neighbor 2a01:b000:1046:10:1::1 remote-as 65101
  
  address-family ipv6 unicast
    network 2a01:b000:1046:10:1::100/128
    neighbor 2a01:b000:1046:10:1::1 activate
  exit-address-family

exit
write memory
```

**Repeat for dns-2 (ASN 65202, router-id 10.1.0.51) and dns-3 (ASN 65203, router-id 10.1.0.52).**

**Key Point:** All 3 nodes advertise **same prefix** `2a01:b000:1046:10:1::100/128`!

---

### Verify BGP Sessions

```bash
sudo vtysh -c 'show bgp ipv6 unicast summary'
```

**Expected (on all nodes):**
```
Neighbor              V   AS  MsgRcvd MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
2a01:b000:1046:10:1::1 4 65101      5       7        0    0    0 00:02:00            0
```

---

**Check advertised routes:**
```bash
sudo vtysh -c 'show bgp ipv6 unicast'
```

**Expected:**
```
   Network                      Next Hop            Metric LocPrf Weight Path
*> 2a01:b000:1046:10:1::100/128 ::                       0         32768 i
```

---

## Step 6: Verify Anycast in CloudStack

```bash
cloudmonkey list bgp guest routes prefix=2a01:b000:1046:10:1::100/128
```

**Expected:**
```json
{
  "count": 3,
  "bgpguestroute": [
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::50"},
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::51"},
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::52"}
  ]
}
```

**VR has 3 routes for same prefix → ECMP (Equal-Cost Multi-Path)!**

---

### Verify VR Routing Table

```bash
ssh root@<vr-ip>
ip -6 route show 2a01:b000:1046:10:1::100
```

**Expected:**
```
2a01:b000:1046:10:1::100 proto bgp metric 20
    nexthop via 2a01:b000:1046:10:1::50 dev eth1 weight 1
    nexthop via 2a01:b000:1046:10:1::51 dev eth1 weight 1
    nexthop via 2a01:b000:1046:10:1::52 dev eth1 weight 1
```

**ECMP enabled!** Traffic is load-balanced across all 3 DNS servers.

---

## Step 7: Test DNS Queries

### Query from Client

```bash
dig @2a01:b000:1046:10:1::100 example.com AAAA
```

**Expected Response:**
```
; <<>> DiG 9.18.12 <<>> @2a01:b000:1046:10:1::100 example.com AAAA
;; ANSWER SECTION:
example.com.        300     IN      AAAA    2001:db8::1
```

✅ **DNS query successful!**

---

### Test Load Balancing

Run multiple queries:

```bash
for i in {1..30}; do
  dig @2a01:b000:1046:10:1::100 example.com +short
done
```

**Check which server handled queries:**

```bash
# On dns-1:
sudo journalctl -u bind9 -f | grep "query"

# On dns-2:
sudo journalctl -u bind9 -f | grep "query"

# On dns-3:
sudo journalctl -u bind9 -f | grep "query"
```

**Expected:** Queries distributed across all 3 servers (roughly 10 queries each).

---

## Step 8: Failover Test

### Simulate DNS Server Failure

```bash
# On dns-1:
sudo systemctl stop bind9
sudo systemctl stop frr
```

**What happens:**
1. BGP session from dns-1 to VR drops
2. VR removes route via `...::50`
3. VR updates ECMP: Only 2 next hops remain (dns-2, dns-3)
4. Clients' queries automatically routed to dns-2 or dns-3

---

### Verify Failover

**In CloudStack:**
```bash
cloudmonkey list bgp guest routes prefix=2a01:b000:1046:10:1::100/128
```

**Expected:**
```json
{
  "count": 2,
  "bgpguestroute": [
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::51"},
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "2a01:b000:1046:10:1::52"}
  ]
}
```

**dns-1 route removed!**

---

**VR routing table:**
```bash
ip -6 route show 2a01:b000:1046:10:1::100
```

**Expected:**
```
2a01:b000:1046:10:1::100 proto bgp metric 20
    nexthop via 2a01:b000:1046:10:1::51 dev eth1 weight 1
    nexthop via 2a01:b000:1046:10:1::52 dev eth1 weight 1
```

**Only 2 next hops!**

---

### Test Client Connectivity

```bash
dig @2a01:b000:1046:10:1::100 example.com AAAA
```

**Expected:**
```
; <<>> DiG 9.18.12 <<>> @2a01:b000:1046:10:1::100 example.com AAAA
;; ANSWER SECTION:
example.com.        300     IN      AAAA    2001:db8::1
```

✅ **Still works!** Queries handled by dns-2 and dns-3.

---

### Failover Timeline

```
T+0s:   dns-1 stops (bind9 + FRR down)
T+1s:   BGP session timeout (keepalive missed)
T+2s:   VR removes route via ...::50
T+3s:   VR updates ECMP (2 next hops)
T+3s:   New queries routed to dns-2/dns-3

Total failover time: ~3 seconds
```

---

## Step 9: Restore dns-1

```bash
# On dns-1:
sudo systemctl start frr
sudo systemctl start bind9
```

**BGP session re-establishes, route re-advertised, ECMP restored to 3 next hops.**

---

## Monitoring

### DNS Query Rate

```bash
# On any DNS server:
sudo rndc stats
cat /var/cache/bind/named.stats | grep "queries resulted in successful answer"
```

---

### BGP Session Health

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

### ECMP Load Distribution

**Check VR traffic counters:**
```bash
ssh root@<vr-ip>
ip -6 -s route show 2a01:b000:1046:10:1::100
```

**Example output:**
```
2a01:b000:1046:10:1::100 proto bgp metric 20 used 1234 mtu 1500
    nexthop via ...::50 dev eth1 weight 1 used 412
    nexthop via ...::51 dev eth1 weight 1 used 420
    nexthop via ...::52 dev eth1 weight 1 used 402
```

**"used" counter shows packets sent to each next hop (balanced).**

---

## Advanced: Geographic Anycast

### Multi-Zone Deployment

**Scenario:** Deploy DNS servers in 2 CloudStack zones (London + Sofia)

```
Zone: London
- dns-london-1: 2a01:b000:1046:10:1::50 (ASN 65201)
- dns-london-2: 2a01:b000:1046:10:1::51 (ASN 65202)

Zone: Sofia
- dns-sofia-1: 2a01:b000:1046:20:1::50 (ASN 65203)
- dns-sofia-2: 2a01:b000:1046:20:1::51 (ASN 65204)

All advertise: 2a01:b000:1046::100/128 (shared anycast IP)
```

**BGP Preference:**
- London clients → Routed to dns-london-* (shorter path)
- Sofia clients → Routed to dns-sofia-* (shorter path)

**Implementation:**
- Use BGP AS_PATH prepending or local-pref to prefer local zone
- CloudStack BGP supports this via VNF advanced policies (future feature)

---

## Troubleshooting

### Issue: Only One Server Receives Queries

**Diagnosis:**
```bash
ip -6 route show 2a01:b000:1046:10:1::100
```

**If only 1 next hop shown:**

**Cause:** ECMP not enabled in Linux kernel

**Solution:**
```bash
# Enable ECMP on VR
ssh root@<vr-ip>
sysctl -w net.ipv6.fib_multipath_hash_policy=1
echo "net.ipv6.fib_multipath_hash_policy=1" >> /etc/sysctl.conf
```

**Hash policy:**
- `0` = Layer 3 only (src/dst IP)
- `1` = Layer 4 (src/dst IP + port) → Better load balancing

---

### Issue: BIND9 Not Listening on Anycast IP

**Diagnosis:**
```bash
sudo netstat -tulnp | grep :53
```

**If only node IP shown, not anycast IP:**

**Solution:**
```bash
# Add anycast IP to listen-on-v6
sudo vi /etc/bind/named.conf.options
# Ensure: listen-on-v6 { 2a01:b000:1046:10:1::100; ... };
sudo systemctl restart bind9
```

---

### Issue: BGP Route Flapping

**Diagnosis:**
```bash
cloudmonkey list bgp guest peering events eventtype=SESSION_DOWN
```

**Cause:** FRR process restarting frequently

**Solution:**
```bash
# Check FRR logs
sudo journalctl -u frr -n 100

# Common issue: BGP config syntax error
sudo vtysh -c 'show running-config'
```

---

## Performance Tuning

### Increase DNS Query Rate

**BIND9 tuning (`/etc/bind/named.conf.options`):**

```
options {
    // Increase worker threads
    worker-threads: 4;
    
    // Increase max cache
    max-cache-size 512M;
    
    // Disable query logging (reduce I/O)
    querylog no;
};
```

---

### BGP Keepalive Tuning

**Faster failure detection:**

```bash
sudo vtysh
configure terminal
router bgp 65201
  neighbor 2a01:b000:1046:10:1::1 timers 5 15
exit
write memory
```

**Timers: 5 seconds keepalive, 15 seconds hold time**

**Trade-off:** More frequent BGP packets.

---

## Security

### Rate Limiting

**BIND9 rate limiting (`/etc/bind/named.conf.options`):**

```
rate-limit {
    responses-per-second 100;
    window 5;
};
```

**Prevents DNS amplification attacks.**

---

### DNSSEC

**Sign DNS zone:**

```bash
cd /etc/bind/zones
sudo dnssec-keygen -a RSASHA256 -b 2048 -n ZONE example.com
sudo dnssec-signzone -o example.com db.example.com
```

**Update zone file reference:**
```bash
# /etc/bind/named.conf.local
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com.signed";
};
```

---

## Summary

✅ **Achieved:**
- High-availability DNS with anycast
- Automatic load balancing (ECMP)
- Sub-3-second failover
- Scalable architecture (add more servers → advertise same IP)

**Key Benefits:**
- **No Single Point of Failure:** Any server can fail, service continues
- **Geographic Load Balancing:** Clients routed to nearest server
- **Simple Client Config:** Clients use single IP, no DNS resolver lists

---

## Next Steps

- **Extend to Authoritative DNS:**
  - Add secondary zones with zone transfers
  - Deploy hidden master + anycast slaves

- **Recursive DNS:**
  - Deploy recursive resolvers with anycast
  - Use for internal network DNS

- **CDN-style Anycast:**
  - Apply same pattern to HTTP(S) services
  - Nginx/HAProxy with anycast VIPs

---

**Reference Files:**
- BIND Config: `/etc/bind/named.conf.options`
- Zone File: `/etc/bind/zones/db.example.com`
- FRR Config: `/etc/frr/frr.conf`

**Last Updated:** November 20, 2025
