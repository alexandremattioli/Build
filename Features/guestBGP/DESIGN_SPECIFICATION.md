# Guest-Side BGP Peering - Technical Design Specification

**Feature:** VR Guest-Side BGP Peering  
**Target Release:** CloudStack 4.23 (Q2 2025)  
**Design Phase:** MVP (Minimum Viable Product)  
**Author:** Alexandre Mattioli (@alexandremattioli)  
**Date:** November 20, 2025

---

## Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **BGP Mode** | Passive (VR listens) | Tenant controls timing, simpler security |
| **IP Version** | IPv6 Phase 1, IPv4 Phase 2 | Matches existing VR capabilities, faster delivery |
| **Configuration Scope** | Network Offering level | Simple admin config, tenant opt-in via BGP daemon |
| **VRRP Support** | Not in MVP (Phase 3) | Single VR only, reduces complexity |
| **Prefix Lengths** | Configurable (default /128 only) | Flexible yet secure, admin-controlled |
| **BGP Communities** | Not in MVP (Phase 3) | Simplifies implementation, covers 80% use cases |
| **Route Redistribution** | Automatic after validation | Real-time failover support, matches VR behavior |
| **Monitoring** | CloudStack API only | MVP simplicity, defer Prometheus to Phase 2 |

---

## Architecture Overview

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  CloudStack Management Server                │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Network Offering Configuration                      │  │
│  │  - guestBgpPeeringEnabled: boolean                   │  │
│  │  - guestBgpMinPrefixLength: int (default 128)        │  │
│  │  - guestBgpMaxPrefixLength: int (default 128)        │  │
│  │  - guestBgpMaxPrefixes: int (default 10)             │  │
│  │  - guestBgpAllowedAsn: string (e.g., "65200-65299")  │  │
│  └──────────────────────────────────────────────────────┘  │
│                           ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  VR Config Generator                                 │  │
│  │  - Generates FRR bgpd.conf with guest BGP listener   │  │
│  │  - Creates prefix-lists from network CIDR            │  │
│  │  - Applies security policies (max-prefix, filters)   │  │
│  └──────────────────────────────────────────────────────┘  │
│                           ↓                                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  BGP Peering State Tracker (Database)                │  │
│  │  - bgp_guest_peering table                           │  │
│  │  - Tracks session state, metrics, audit log          │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │ Config push via VR agent
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    Virtual Router (VR)                       │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  FRR Daemon (bgpd)                                   │  │
│  │                                                       │  │
│  │  Upstream BGP (existing):                            │  │
│  │    neighbor 2a01:b000:1046:0:0::1 (ZoneA-Core)      │  │
│  │    remote-as 64510                                   │  │
│  │                                                       │  │
│  │  Guest BGP Listener (NEW):                           │  │
│  │    bgp listen range 2a01:b000:1046:10:1::/64        │  │
│  │    neighbor TENANT_VMS peer-group                    │  │
│  │    remote-as 65200-65299                             │  │
│  │    maximum-prefix 10                                 │  │
│  │    route-map TENANT_FILTER in                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                           ↑ BGP TCP/179                      │
└───────────────────────────┼──────────────────────────────────┘
                            │
┌───────────────────────────┼──────────────────────────────────┐
│  Guest Network (2a01:b000:1046:10:1::/64)                   │
│                           │                                  │
│  ┌────────────────────────┴───────────────────────────┐     │
│  │  Tenant VM (e.g., Kubernetes Node)                 │     │
│  │                                                     │     │
│  │  ┌───────────────────────────────────────────┐    │     │
│  │  │  FRR/BIRD/ExaBGP (BGP Speaker)            │    │     │
│  │  │                                            │    │     │
│  │  │  neighbor 2a01:b000:1046:10:1::1 (VR)     │    │     │
│  │  │  remote-as 65101                           │    │     │
│  │  │  local-as 65201                            │    │     │
│  │  │                                            │    │     │
│  │  │  Announces:                                │    │     │
│  │  │    2a01:b000:1046:10:1::100/128 (VIP)     │    │     │
│  │  └───────────────────────────────────────────┘    │     │
│  │                                                     │     │
│  │  Application: MetalLB / Patroni / Custom           │     │
│  └─────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## Network Offering Schema Changes

### New Parameters

```sql
-- Add to cloud.network_offerings table
ALTER TABLE network_offerings ADD COLUMN guest_bgp_peering_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE network_offerings ADD COLUMN guest_bgp_min_prefix_length INT DEFAULT 128;
ALTER TABLE network_offerings ADD COLUMN guest_bgp_max_prefix_length INT DEFAULT 128;
ALTER TABLE network_offerings ADD COLUMN guest_bgp_max_prefixes INT DEFAULT 10;
ALTER TABLE network_offerings ADD COLUMN guest_bgp_allowed_asn_min INT DEFAULT 65200;
ALTER TABLE network_offerings ADD COLUMN guest_bgp_allowed_asn_max INT DEFAULT 65299;
```

### Example Network Offering

```yaml
Name: "Isolated Network with Guest BGP"
Guest Type: Isolated
Traffic Type: Guest
Specify VLAN: No
Supported Services:
  - DHCP
  - DNS
  - Firewall
  - Load Balancer
  - Source NAT
  - Static NAT
  - VPN
  - Dynamic Routing (BGP) ← Existing

# New parameters for guest-side BGP
Guest BGP Peering Enabled: true
Guest BGP Min Prefix Length: 128  # Only /128 (single IPs) allowed
Guest BGP Max Prefix Length: 128
Guest BGP Max Prefixes: 10         # Rate limiting
Guest BGP Allowed ASN Range: 65200-65299  # 100 ASNs for tenants
```

---

## Database Schema

### New Table: bgp_guest_peering

```sql
CREATE TABLE bgp_guest_peering (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  uuid VARCHAR(40) NOT NULL UNIQUE,
  
  -- Relations
  network_id BIGINT UNSIGNED NOT NULL,
  vm_id BIGINT UNSIGNED NOT NULL,
  nic_id BIGINT UNSIGNED NOT NULL,
  
  -- BGP Parameters
  guest_asn INT UNSIGNED NOT NULL,
  guest_ip VARCHAR(45) NOT NULL,  -- IPv6 address
  vr_asn INT UNSIGNED NOT NULL,
  vr_ip VARCHAR(45) NOT NULL,
  
  -- Session State
  state VARCHAR(32) NOT NULL,  -- Idle, Connect, Active, OpenSent, OpenConfirm, Established
  uptime_seconds BIGINT,
  prefixes_received INT DEFAULT 0,
  prefixes_sent INT DEFAULT 0,
  last_error VARCHAR(255),
  
  -- Metadata
  created DATETIME NOT NULL,
  last_updated DATETIME,
  removed DATETIME,
  
  CONSTRAINT fk_bgp_guest_network FOREIGN KEY (network_id) REFERENCES networks(id) ON DELETE CASCADE,
  CONSTRAINT fk_bgp_guest_vm FOREIGN KEY (vm_id) REFERENCES vm_instance(id) ON DELETE CASCADE,
  CONSTRAINT fk_bgp_guest_nic FOREIGN KEY (nic_id) REFERENCES nics(id) ON DELETE CASCADE,
  
  INDEX idx_network (network_id),
  INDEX idx_vm (vm_id),
  INDEX idx_state (state),
  INDEX idx_removed (removed)
) ENGINE=InnoDB;
```

### New Table: bgp_guest_routes

```sql
CREATE TABLE bgp_guest_routes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  uuid VARCHAR(40) NOT NULL UNIQUE,
  
  -- Relations
  peering_id BIGINT UNSIGNED NOT NULL,
  
  -- Route Details
  prefix VARCHAR(64) NOT NULL,      -- e.g., "2a01:b000:1046:10:1::100/128"
  prefix_length INT NOT NULL,
  next_hop VARCHAR(45) NOT NULL,
  
  -- Route State
  state VARCHAR(32) NOT NULL,       -- Received, Accepted, Rejected, Withdrawn
  rejection_reason VARCHAR(255),    -- e.g., "Prefix not in allowed range"
  
  -- Metrics
  received_at DATETIME NOT NULL,
  accepted_at DATETIME,
  withdrawn_at DATETIME,
  
  CONSTRAINT fk_bgp_route_peering FOREIGN KEY (peering_id) REFERENCES bgp_guest_peering(id) ON DELETE CASCADE,
  
  INDEX idx_peering (peering_id),
  INDEX idx_state (state),
  INDEX idx_prefix (prefix)
) ENGINE=InnoDB;
```

---

## VR Configuration Generation

### FRR bgpd.conf Template

```bash
# Generated by CloudStack for network: {{ network_name }} ({{ network_id }})
# Guest BGP Peering Enabled: {{ guest_bgp_enabled }}

router bgp {{ vr_asn }}
 bgp router-id {{ vr_ipv4_address }}
 no bgp ebgp-requires-policy
 
 # Upstream peering (existing - already configured)
 neighbor {{ zone_router_ipv6 }} remote-as {{ zone_asn }}
 neighbor {{ zone_router_ipv6 }} description ZoneA-Core
 
 {% if guest_bgp_enabled %}
 # Guest network BGP listener (PASSIVE MODE)
 bgp listen range {{ guest_network_cidr }} peer-group TENANT_VMS
 neighbor TENANT_VMS peer-group
 neighbor TENANT_VMS remote-as {{ guest_asn_min }}-{{ guest_asn_max }}
 neighbor TENANT_VMS maximum-prefix {{ max_prefixes }}
 neighbor TENANT_VMS description "Tenant VM BGP Peers"
 {% endif %}
 
 address-family ipv6 unicast
  neighbor {{ zone_router_ipv6 }} activate
  {% if guest_bgp_enabled %}
  neighbor TENANT_VMS activate
  neighbor TENANT_VMS route-map TENANT_FILTER in
  neighbor TENANT_VMS route-map TO_UPSTREAM out
  {% endif %}
 exit-address-family
!
{% if guest_bgp_enabled %}
# Prefix filtering: Only accept prefixes within guest network CIDR
ipv6 prefix-list TENANT_ALLOWED seq 10 permit {{ guest_network_cidr }} le {{ max_prefix_length }} ge {{ min_prefix_length }}
!
# Inbound route-map: Validate tenant routes
route-map TENANT_FILTER permit 10
 match ipv6 address prefix-list TENANT_ALLOWED
 set local-preference 100
!
route-map TENANT_FILTER deny 20
!
# Outbound route-map: Re-advertise accepted tenant routes to upstream
route-map TO_UPSTREAM permit 10
 # Automatically redistribute guest-learned routes
!
{% endif %}
```

### Example Generated Config

```bash
# Network: tenant-k8s-network (net-12345)
# Guest CIDR: 2a01:b000:1046:10:1::/64

router bgp 65101
 bgp router-id 10.88.88.71
 no bgp ebgp-requires-policy
 
 neighbor 2a01:b000:1046:0:0::1 remote-as 64510
 neighbor 2a01:b000:1046:0:0::1 description ZoneA-Core
 
 bgp listen range 2a01:b000:1046:10:1::/64 peer-group TENANT_VMS
 neighbor TENANT_VMS peer-group
 neighbor TENANT_VMS remote-as 65200-65299
 neighbor TENANT_VMS maximum-prefix 10
 neighbor TENANT_VMS description "Tenant VM BGP Peers"
 
 address-family ipv6 unicast
  neighbor 2a01:b000:1046:0:0::1 activate
  neighbor TENANT_VMS activate
  neighbor TENANT_VMS route-map TENANT_FILTER in
  neighbor TENANT_VMS route-map TO_UPSTREAM out
 exit-address-family
!
ipv6 prefix-list TENANT_ALLOWED seq 10 permit 2a01:b000:1046:10:1::/64 le 128 ge 128
!
route-map TENANT_FILTER permit 10
 match ipv6 address prefix-list TENANT_ALLOWED
 set local-preference 100
!
route-map TENANT_FILTER deny 20
!
route-map TO_UPSTREAM permit 10
!
```

---

## Security Controls

### 1. Prefix Validation (Primary Defense)

**Threat:** Tenant advertises arbitrary prefixes (e.g., 0::/0, other tenant's networks)

**Mitigation:**
```bash
# Only accept prefixes within tenant's allocated guest network CIDR
ipv6 prefix-list TENANT_ALLOWED seq 10 permit 2a01:b000:1046:10:1::/64 le 128 ge 128

# Tenant attempts to advertise 2a01:b000:1046:20:1::/64 (another tenant)
# → Rejected by prefix-list (not in 10:1::/64 range)
```

**Validation Logic:**
1. Extract guest network CIDR from CloudStack database
2. Generate prefix-list: `permit <guest_cidr> le <max_len> ge <min_len>`
3. Apply to inbound route-map
4. Log rejected routes to `bgp_guest_routes` table with rejection_reason

---

### 2. Rate Limiting (Max-Prefix)

**Threat:** Tenant floods route table with thousands of prefixes

**Mitigation:**
```bash
neighbor TENANT_VMS maximum-prefix 10

# Tenant advertises 11th prefix:
# BGP session tears down with error: "Maximum-prefix limit exceeded"
```

**Behavior:**
- Session terminates on violation
- Auto-restart after 5-minute penalty (FRR default)
- CloudStack logs violation to `bgp_guest_peering` table (last_error field)

---

### 3. ASN Range Validation

**Threat:** Tenant uses reserved or already-allocated ASNs

**Mitigation:**
```bash
neighbor TENANT_VMS remote-as 65200-65299

# Tenant attempts AS 64510 (ZoneA-Core's ASN) → Rejected
# Tenant attempts AS 64512 (RFC reserved) → Rejected
# Tenant uses AS 65201 → Accepted
```

**ASN Allocation:**
- Default range: 65200-65299 (100 ASNs for tenant use)
- Configurable per network offering
- Prevents conflicts with infrastructure ASNs (64500-64999)

---

### 4. Automatic Route Withdrawal on VM Shutdown

**Threat:** Stale routes after VM termination

**Mitigation:**
1. VM shuts down → BGP session drops (TCP connection closed)
2. FRR automatically withdraws all routes learned from that session
3. VR propagates withdrawal to upstream (convergence <5s with BFD)

**CloudStack Hook:**
- On VM stop/destroy: Update `bgp_guest_peering` state to "Withdrawn"
- On VM expunge: Delete `bgp_guest_peering` record

---

## Data Flow: Route Advertisement

### Sequence Diagram

```
Tenant VM          VR (FRR)          CloudStack MS          Zone Router
    |                  |                    |                     |
    | 1. Start FRR     |                    |                     |
    |----------------->|                    |                     |
    |                  |                    |                     |
    | 2. BGP OPEN      |                    |                     |
    |----------------->|                    |                     |
    |                  | 3. Validate ASN    |                     |
    |                  | (65200-65299?)     |                     |
    |                  |-------|            |                     |
    |                  |       |            |                     |
    |                  |<------|            |                     |
    |                  |                    |                     |
    | 4. BGP OPEN (ACK)|                    |                     |
    |<-----------------|                    |                     |
    |                  |                    |                     |
    | 5. BGP UPDATE    |                    |                     |
    | (announce ::100/128)                  |                     |
    |----------------->|                    |                     |
    |                  | 6. Validate prefix |                     |
    |                  | (in 10:1::/64?)    |                     |
    |                  |-------|            |                     |
    |                  |       |            |                     |
    |                  |<------| (ACCEPT)   |                     |
    |                  |                    |                     |
    |                  | 7. Log route       |                     |
    |                  |------------------->|                     |
    |                  |   (INSERT bgp_guest_routes)              |
    |                  |                    |                     |
    |                  | 8. Advertise upstream                    |
    |                  |------------------------------------->    |
    |                  |   (2a01:b000:1046:10:1::100/128)         |
    |                  |                                          |
    |                  |                    | 9. Update state     |
    |                  |<-------------------|                     |
    |                  |   (state=Established, prefixes_received=1)
    |                  |                    |                     |
```

### Step-by-Step Flow

**Step 1-4: BGP Session Establishment**
1. Tenant VM starts BGP daemon (FRR/BIRD/ExaBGP)
2. VM sends BGP OPEN to VR (neighbor 2a01:b000:1046:10:1::1)
3. VR validates: ASN in allowed range (65200-65299)?
4. VR responds with OPEN (session Established)
5. CloudStack logs session to `bgp_guest_peering` table

**Step 5-6: Route Advertisement**
1. Tenant VM sends BGP UPDATE: `2a01:b000:1046:10:1::100/128`
2. VR applies route-map TENANT_FILTER:
   - Check prefix-list: Is `::100/128` within `10:1::/64`? → YES
   - Check prefix length: Is /128 between min/max (128-128)? → YES
   - Accept route, set local-preference 100

**Step 7: Audit Logging**
1. VR agent reports route to CloudStack Management Server
2. CloudStack inserts record into `bgp_guest_routes`:
   ```sql
   INSERT INTO bgp_guest_routes (
     peering_id, prefix, prefix_length, next_hop, state, received_at
   ) VALUES (
     123, '2a01:b000:1046:10:1::100/128', 128, '2a01:b000:1046:10:1::50', 'Accepted', NOW()
   );
   ```

**Step 8: Upstream Redistribution**
1. VR applies route-map TO_UPSTREAM (permit all accepted tenant routes)
2. VR advertises to ZoneA-Core (2a01:b000:1046:0:0::1)
3. ZoneA-Core propagates to ISP1-Core
4. Route appears in global IPv6 table

**Step 9: State Update**
1. CloudStack polls VR for BGP stats (via vtysh or FRR API)
2. Updates `bgp_guest_peering`:
   ```sql
   UPDATE bgp_guest_peering SET
     state = 'Established',
     uptime_seconds = 300,
     prefixes_received = 1,
     last_updated = NOW()
   WHERE id = 123;
   ```

---

## Error Handling

### Scenario 1: Invalid Prefix (Out of Range)

**Trigger:** Tenant advertises `2a01:b000:1046:20:1::100/128` (different network)

**VR Behavior:**
```
% BGP: Inbound soft reconfiguration not enabled
% BGP: 2a01:b000:1046:20:1::100/128 filtered by prefix-list TENANT_ALLOWED
```

**CloudStack Action:**
```sql
INSERT INTO bgp_guest_routes (
  peering_id, prefix, state, rejection_reason, received_at
) VALUES (
  123, '2a01:b000:1046:20:1::100/128', 'Rejected', 
  'Prefix not in allowed range (2a01:b000:1046:10:1::/64)', NOW()
);
```

**User Visibility:**
- API: `listBgpGuestRoutes peeringid=123 state=Rejected`
- Returns rejected routes with rejection_reason

---

### Scenario 2: Max-Prefix Violation

**Trigger:** Tenant advertises 11th prefix (limit: 10)

**VR Behavior:**
```
%BGP: 2a01:b000:1046:10:1::50 [65201] Maximum-prefix limit 10 exceeded - session cleared
%BGP: Notification sent to neighbor 2a01:b000:1046:10:1::50 (Cease/Maximum Number of Prefixes Reached)
```

**CloudStack Action:**
```sql
UPDATE bgp_guest_peering SET
  state = 'Idle',
  last_error = 'Max-prefix limit (10) exceeded',
  last_updated = NOW()
WHERE id = 123;
```

**Recovery:**
- BGP session auto-restarts after 5 minutes (FRR default)
- Tenant must reduce advertised prefixes to re-establish

---

### Scenario 3: Invalid ASN

**Trigger:** Tenant attempts to peer with ASN 64510 (reserved for ZoneA-Core)

**VR Behavior:**
```
%BGP: 2a01:b000:1046:10:1::50 [64510] OPEN has invalid AS number - session rejected
```

**CloudStack Action:**
- No entry created in `bgp_guest_peering` (session never established)
- VR logs error to syslog

---

## Performance Considerations

### Scale Targets (MVP)

| Metric | Target | Notes |
|--------|--------|-------|
| BGP sessions per VR | 100 | FRR supports 1000+, limit for MVP safety |
| Routes per session | 10 | Configurable via max-prefix |
| Total routes per VR | 1,000 | 100 sessions × 10 routes |
| Session establishment time | <5 seconds | TCP + BGP OPEN handshake |
| Route propagation time | <2 seconds | VR → Zone Router |
| Convergence on failure | <5 seconds | With BFD (Phase 2) |

### VR Resource Impact

**Baseline (no guest BGP):**
- CPU: 5-10% idle
- RAM: 512 MB
- FRR processes: bgpd, zebra, staticd

**With Guest BGP (100 sessions, 1000 routes):**
- CPU: 15-20% (bgpd processing)
- RAM: 768 MB (+256 MB for route table)
- Network: ~1 Mbps (BGP keepalives 60s interval)

**Recommendation:** VR minimum spec for guest BGP:
- 2 vCPU
- 1 GB RAM
- 10 GB disk

---

## Testing Strategy

### Unit Tests

**Test 1: Prefix Validation**
```python
def test_prefix_validation():
    guest_cidr = "2a01:b000:1046:10:1::/64"
    
    # Valid prefixes
    assert validate_prefix("2a01:b000:1046:10:1::100/128", guest_cidr) == True
    assert validate_prefix("2a01:b000:1046:10:1::/64", guest_cidr) == True
    
    # Invalid prefixes
    assert validate_prefix("2a01:b000:1046:20:1::100/128", guest_cidr) == False
    assert validate_prefix("2a01:b000:1046::/48", guest_cidr) == False
    assert validate_prefix("0::/0", guest_cidr) == False
```

**Test 2: ASN Range Validation**
```python
def test_asn_validation():
    asn_min, asn_max = 65200, 65299
    
    assert validate_asn(65201, asn_min, asn_max) == True
    assert validate_asn(64510, asn_min, asn_max) == False  # Infrastructure ASN
    assert validate_asn(70000, asn_min, asn_max) == False  # Out of range
```

### Integration Tests

**Test 3: BGP Session Establishment**
```bash
# Setup: Deploy VR with guest BGP enabled
# Action: Start FRR on test VM, peer with VR
# Verify: Session reaches Established state
# Verify: CloudStack DB reflects session state

cmk list bgp peering sessions networkid=net-123 | grep Established
```

**Test 4: Route Acceptance**
```bash
# Setup: Established BGP session
# Action: Announce valid prefix from VM
# Verify: VR accepts route
# Verify: Route appears in CloudStack DB
# Verify: Route propagated to upstream router

vtysh -c 'show bgp ipv6 unicast 2a01:b000:1046:10:1::100/128'
```

**Test 5: Route Rejection**
```bash
# Action: Announce invalid prefix (different network)
# Verify: VR rejects route
# Verify: Route marked as "Rejected" in DB with reason
# Verify: Route NOT propagated upstream

cmk list bgp guest routes peeringid=peer-123 state=Rejected
```

**Test 6: Max-Prefix Enforcement**
```bash
# Action: Announce 11 prefixes (limit: 10)
# Verify: Session tears down on 11th prefix
# Verify: Last error: "Max-prefix limit exceeded"
# Verify: Session auto-restarts after 5 minutes
```

### Performance Tests

**Test 7: Scale (100 Sessions)**
```bash
# Deploy 100 VMs with BGP enabled
# Verify: All sessions establish successfully
# Measure: VR CPU/RAM usage
# Target: <20% CPU, <1 GB RAM
```

**Test 8: Convergence Time**
```bash
# Setup: VM advertising route
# Action: Stop VM (simulate failure)
# Measure: Time until route withdrawn from upstream
# Target: <5 seconds
```

---

## Migration Path (Existing Deployments)

### Current State (No Guest BGP)

```
Tenant deploys VNF appliance as BGP intermediary:
  VM → VNF (FRR) → VR → Zone Router
  
Issues:
  - Complex setup (deploy + configure VNF)
  - Resource overhead (VNF consumes vCPU/RAM)
  - Security gaps (manual prefix filtering)
```

### Future State (Native Guest BGP)

```
Tenant peers directly with VR:
  VM → VR → Zone Router
  
Benefits:
  - Simple (no VNF required)
  - Efficient (no intermediary overhead)
  - Secure (automatic prefix validation)
```

### Migration Steps

1. **Upgrade CloudStack to 4.23+**
2. **Create new network offering** with `guestBgpPeeringEnabled=true`
3. **Deploy test network** using new offering
4. **Reconfigure tenant VMs** to peer with VR (change neighbor IP from VNF to VR)
5. **Validate routes** appear in `listBgpPeeringSessions` API
6. **Decommission VNF** appliances
7. **Update firewall rules** (allow TCP/179 from guest network to VR)

---

## Future Enhancements (Post-MVP)

### Phase 2: Advanced Features (CloudStack 4.24)
- BFD for fast failure detection (<1s convergence)
- IPv4 support (dual-stack BGP)
- BGP MD5 authentication (per-session passwords)
- Prometheus metrics export
- Grafana dashboards

### Phase 3: Enterprise Features (CloudStack 4.25+)
- BGP communities for traffic engineering
- VRRP support (peer with both VRs)
- Route filtering by tag/label
- Multi-VR HA with graceful restart
- UI for BGP session management (Primate)

---

## References

- **Feature Overview:** `/Builder2/Build/Features/guestBGP/README.md`
- **API Specification:** `/Builder2/Build/Features/guestBGP/API_SPECIFICATION.md` (TBD)
- **Security Model:** `/Builder2/Build/Features/guestBGP/SECURITY_MODEL.md` (TBD)
- **FRR Documentation:** https://docs.frrouting.org/en/latest/bgp.html
- **CloudStack VR Architecture:** https://docs.cloudstack.apache.org/en/latest/adminguide/virtual_router.html

---

**Status:** Design Complete - Ready for Implementation Planning  
**Next Steps:** Create API specification and implementation plan  
**Last Updated:** November 20, 2025
