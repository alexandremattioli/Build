# Guest-Side BGP Peering for CloudStack Virtual Routers

**Feature Status:** 🚧 Design Phase (Target: CloudStack 4.23/4.24)  
**Author:** Alexandre Mattioli (@alexandremattioli)  
**Organization:** ShapeBlue  
**Date:** November 20, 2025

---

## Executive Summary

Enable CloudStack Virtual Routers (VRs) to accept BGP peering sessions **from tenant VMs** on guest networks, allowing tenants to dynamically advertise service IPs, anycast VIPs, and floating IPs without requiring separate VNF appliances or manual configuration.

### Current Limitation (CloudStack 4.21)
- VRs only peer BGP with **upstream zone routers**
- Guest VMs **cannot** advertise routes via BGP
- Workaround requires deploying VNF appliances (complex, expensive, security gaps)

### Proposed Enhancement (CloudStack 4.23+)
- VRs **listen for BGP connections** on guest network interfaces
- Tenant VMs peer directly with their VR using eBGP
- VR validates routes (prefix filtering, rate limiting) and redistributes to zone fabric
- Built-in security controls (MD5 auth, ASN validation, max-prefix limits)

---

## Use Cases

### 1. Kubernetes LoadBalancer Services (MetalLB Integration)
**Problem:** Kubernetes clusters need external IPs for LoadBalancer-type services  
**Solution:** MetalLB announces service IPs to VR via BGP

**Example:**
```yaml
# Kubernetes Service
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - port: 80
  loadBalancerIP: 2a01:b000:1046:10:1::80
```

**Flow:**
1. MetalLB speaker pod peers with VR (AS 65101 ← AS 65201)
2. Announces `2a01:b000:1046:10:1::80/128` via BGP
3. VR accepts route (validates against guest network CIDR)
4. VR redistributes to ZoneA-Core (AS 64510)
5. External clients reach service via `2a01:b000:1046:10:1::80`

**Value:** Native Kubernetes LoadBalancer support without external load balancers

---

### 2. Database Floating VIPs (PostgreSQL Patroni, MySQL Group Replication)
**Problem:** Database HA requires floating IPs that move between nodes  
**Solution:** Active database node announces VIP via BGP; on failover, standby withdraws old route and announces new

**Example (PostgreSQL Patroni):**
```bash
# Primary node (active)
$ vtysh -c 'show bgp ipv6 summary'
Neighbor            V   AS  MsgRcvd MsgSent   Uptime State
2a01:...::1 (VR)    4 65101     120     118  1h00m00s Established

$ vtysh -c 'show bgp ipv6 unicast 2a01:b000:1046:10:1::100/128'
BGP routing table entry for 2a01:b000:1046:10:1::100/128
Paths: (1 available)
  Local
    :: from :: (10.88.88.100)
      Origin IGP, metric 0, localpref 100, valid, sourced
```

**Flow:**
1. Primary DB announces `2a01:b000:1046:10:1::100/128`
2. Application connects to `2a01:b000:1046:10:1::100` → Primary serves
3. Primary fails → BGP session drops → Route withdrawn
4. Standby promotes to primary → Announces same IP
5. Convergence time: <5 seconds with BFD

**Value:** Zero-downtime database failover without manual IP reassignment

---

### 3. Anycast Services (Multi-Zone Deployment)
**Problem:** Deploy same service IP across multiple zones for geographic load balancing  
**Solution:** Tenant VMs in each zone announce identical anycast IP

**Example:**
```
Zone A (London):
  VM: 2a01:b000:1046:10:1::53/128 (DNS server)
  BGP: Announces to VR-London → ZoneA-Core → ISP1-Core

Zone B (Sofia):
  VM: 2a01:b000:1046:10:1::53/128 (Same DNS server)
  BGP: Announces to VR-Sofia → ZoneB-Core → ISP2-Core

Internet:
  ECMP at ISP cores → 50/50 traffic split
  Zone failure → Automatic failover to remaining zone
```

**Value:** Geographic load balancing and automatic failover (like Cloudflare, AWS Route 53)

---

### 4. Container Service Mesh (Cilium BGP)
**Problem:** Cloud-native apps need dynamic network integration  
**Solution:** Cilium BGP control plane announces pod service IPs to VR

**Example (Cilium):**
```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: cloudstack-vr
spec:
  virtualRouters:
  - localASN: 65201
    neighbors:
    - peerAddress: 2a01:b000:1046:10:1::1/128  # VR guest interface
      peerASN: 65101
    serviceSelector:
      matchLabels:
        bgp-advertise: "true"
```

**Value:** Native integration with modern service mesh architectures

---

## Technical Architecture

### Network Offering Enhancement

**New Parameters (CloudStack 4.23+):**
```yaml
Network Offering:
  name: "Isolated with Guest BGP"
  guestType: Isolated
  dynamicRouting: true
  guestBgpPeeringEnabled: true          # NEW PARAMETER
  
  # Security controls
  guestBgpPrefixFiltering: "strict"     # strict | permissive | custom
  guestBgpMaxPrefixes: 10               # Rate limiting per VM
  guestBgpRequireMd5: true              # Enforce MD5 authentication
  guestBgpAllowedAsn: "65200-65299"     # Restrict tenant ASN range
  guestBgpBfdEnabled: true              # Fast failure detection
```

---

### VR FRR Configuration (Auto-Generated)

```bash
# /etc/frr/bgpd.conf (generated by CloudStack)
router bgp 65101
 bgp router-id 10.88.88.71
 no bgp ebgp-requires-policy
 
 # Upstream peering (existing)
 neighbor 2a01:b000:1046:0:0::1 remote-as 64510
 neighbor 2a01:b000:1046:0:0::1 description ZoneA-Core
 
 # Guest network BGP listener (NEW FEATURE)
 bgp listen range 2a01:b000:1046:10:1::/64 peer-group TENANT_VMS
 neighbor TENANT_VMS peer-group
 neighbor TENANT_VMS remote-as 65200-65299
 neighbor TENANT_VMS password tenant-auto-generated-secret
 neighbor TENANT_VMS maximum-prefix 10
 neighbor TENANT_VMS bfd
 
 address-family ipv6 unicast
  neighbor 2a01:b000:1046:0:0::1 activate
  neighbor TENANT_VMS activate
  neighbor TENANT_VMS route-map TENANT_FILTER in
  neighbor TENANT_VMS route-map TO_CORE out
 exit-address-family
!
# Prefix filtering (only allow tenant-assigned prefixes)
ipv6 prefix-list TENANT_ALLOWED seq 10 permit 2a01:b000:1046:10:1::/64 le 128
!
route-map TENANT_FILTER permit 10
 match ipv6 address prefix-list TENANT_ALLOWED
 set local-preference 100
!
route-map TENANT_FILTER deny 20
!
route-map TO_CORE permit 10
 # Re-advertise accepted tenant routes to zone core
```

---

## Security Controls

### 1. Prefix Filtering (CRITICAL)
**Problem:** Tenants could hijack other networks by advertising arbitrary prefixes  
**Solution:** VR validates all BGP advertisements against tenant's allocated CIDR

**Implementation:**
- **Strict mode** (default): Only accept prefixes within tenant's guest network `/64`
- **Permissive mode**: Accept any prefix from tenant's allocated `/48` block
- **Custom mode**: Admin-defined prefix lists

**Example Attack Prevention:**
```bash
# Tenant A assigned: 2a01:b000:1046:10:1::/64
# Tenant A attempts to advertise: 2a01:b000:1046:20:1::/64 (Tenant B's network)

# VR rejects route
% BGP: [VNQ3Q-1234] Inbound soft reconfiguration not enabled
% BGP: 2a01:b000:1046:20:1::/64 filtered by prefix-list TENANT_ALLOWED
```

---

### 2. Rate Limiting (Max-Prefix)
**Problem:** Tenant could exhaust route table by advertising millions of prefixes  
**Solution:** Limit number of prefixes per tenant VM

**Behavior:**
```bash
# Configured: maximum-prefix 10
# Tenant advertises 11th prefix → BGP session tears down

neighbor 2a01:b000:1046:10:1::100 Maximum-prefix limit 10 exceeded - session cleared
```

**Recovery:** Auto-restart after cooldown period (default: 5 minutes)

---

### 3. BGP MD5 Authentication
**Problem:** Rogue VMs could spoof BGP sessions  
**Solution:** Per-tenant MD5 passwords (auto-generated by CloudStack)

**Implementation:**
```bash
# CloudStack generates unique password per network
neighbor TENANT_VMS password 8f3a9d2c4e1b6f5a7c9e2d4b1a3f6c8e

# Stored in CloudStack DB (encrypted)
# Injected into VR config via systemvm template
```

---

### 4. ASN Validation
**Problem:** Tenant could use reserved or already-allocated ASNs  
**Solution:** Restrict tenant ASNs to specific range

**Example:**
```yaml
guestBgpAllowedAsn: "65200-65299"  # 100 ASNs for tenant use

# Tenant attempts AS 64512 (reserved) → Rejected
# Tenant attempts AS 64510 (ZoneA-Core) → Rejected
# Tenant uses AS 65201 → Accepted
```

---

## CloudStack API Changes

### New API: `configureBgpPeeringForGuest`

**Purpose:** Enable BGP peering for a specific VM  
**User Roles:** Domain Admin, User (if network allows)

**Request:**
```bash
cloudmonkey configure bgp peering for guest \
  virtualmachineid=vm-12345 \
  asn=65201 \
  md5password=optional-custom-password \
  maxprefixes=10 \
  allowedprefixes=2a01:b000:1046:10:1::100/128
```

**Response:**
```json
{
  "bgppeering": {
    "id": "bgp-peer-abc123",
    "vmid": "vm-12345",
    "vmname": "k8s-node-1",
    "asn": 65201,
    "vrneighborip": "2a01:b000:1046:10:1::1",
    "vrasn": 65101,
    "state": "Enabled",
    "sessionstate": "Established",
    "maxprefixes": 10,
    "allowedprefixes": ["2a01:b000:1046:10:1::100/128"],
    "created": "2025-11-20T12:00:00Z"
  }
}
```

---

### New API: `listBgpPeeringSessions`

**Purpose:** List all BGP sessions for a network or VM  
**Filters:** networkid, vmid, state

**Example:**
```bash
cloudmonkey list bgp peering sessions networkid=net-456 state=Established
```

**Response:**
```json
{
  "bgppeeringsession": [
    {
      "id": "bgp-peer-abc123",
      "vmid": "vm-12345",
      "vmip": "2a01:b000:1046:10:1::100",
      "asn": 65201,
      "state": "Established",
      "uptime": "02:15:30",
      "prefixesreceived": 3,
      "prefixessent": 1
    }
  ],
  "count": 1
}
```

---

### New API: `revokeBgpPeeringForGuest`

**Purpose:** Disable BGP peering for a VM  
**Effect:** VR removes neighbor config, tears down session

**Request:**
```bash
cloudmonkey revoke bgp peering for guest virtualmachineid=vm-12345
```

---

## Implementation Roadmap

### Phase 1: Core BGP Peering (CloudStack 4.22 - Q1 2025)
- [ ] Database schema updates (bgp_peering table)
- [ ] Network offering parameters (guestBgpPeeringEnabled, etc.)
- [ ] VR systemvm template update (FRR 8.5+)
- [ ] VR config generator (bgpd.conf templates)
- [ ] Basic prefix filtering (match guest network CIDR)
- [ ] API: configureBgpPeeringForGuest, listBgpPeeringSessions

**Deliverable:** Minimal viable BGP guest peering

---

### Phase 2: Security Hardening (CloudStack 4.23 - Q2 2025)
- [ ] BGP MD5 authentication (auto-generated passwords)
- [ ] Rate limiting (max-prefix enforcement)
- [ ] ASN range validation
- [ ] Audit logging (all BGP route advertisements)
- [ ] Prefix-list customization (per-tenant rules)
- [ ] BFD integration for fast failure detection

**Deliverable:** Production-ready security controls

---

### Phase 3: Advanced Features (CloudStack 4.24 - Q3 2025)
- [ ] BGP community support (traffic engineering)
- [ ] Route filtering by tag/label
- [ ] Multi-VR HA (VRRP + BGP graceful restart)
- [ ] Grafana metrics integration (BGP session state, prefix counts)
- [ ] IPv4 support (currently IPv6-only)
- [ ] UI for BGP session management

**Deliverable:** Enterprise-grade BGP feature parity

---

## Testing Strategy

### Unit Tests
- [ ] VR config generation (bgpd.conf syntax validation)
- [ ] Prefix filtering logic (allowed vs rejected routes)
- [ ] ASN validation (range checks)
- [ ] MD5 password generation (uniqueness, entropy)

### Integration Tests
- [ ] VR BGP session establishment with test VM
- [ ] Route acceptance (valid prefixes)
- [ ] Route rejection (invalid prefixes, max-prefix exceeded)
- [ ] Failover scenarios (VM crash, BGP session timeout)
- [ ] Multi-tenant isolation (Tenant A cannot affect Tenant B)

### Performance Tests
- [ ] Scale: 100 VMs with BGP enabled per network
- [ ] Route table size: 1000 prefixes across all tenants
- [ ] Convergence time: <5 seconds with BFD
- [ ] CPU/memory impact on VR (FRR overhead)

---

## Migration Path from Current Workarounds

### Current Workaround (CloudStack 4.21)
```
Tenant VM → VNF Appliance (FRR) → VR → Zone Router
```
- **Complex:** Requires VNF deployment and configuration
- **Expensive:** VNF consumes vCPU, RAM, storage
- **Security gaps:** No native prefix filtering

### Future Native Support (CloudStack 4.23+)
```
Tenant VM → VR (with guest BGP) → Zone Router
```
- **Simple:** Direct BGP peering with VR
- **Efficient:** No intermediary VNF
- **Secure:** Built-in filtering and rate limiting

**Migration Steps:**
1. Upgrade CloudStack to 4.22+ (or 4.23 for full features)
2. Update network offering: enable `guestBgpPeeringEnabled`
3. Reconfigure tenant VMs to peer with VR directly (change neighbor IP)
4. Decommission VNF appliances
5. Update firewall rules (allow TCP/179 from guest network)

---

## Comparison with Other Platforms

| Feature | CloudStack (Proposed) | AWS VPC | Azure VNet | GCP VPC |
|---------|----------------------|---------|-----------|---------|
| Guest BGP peering | ✅ Native (4.23+) | ❌ No (Direct Connect only) | ❌ No (ExpressRoute only) | ✅ Yes (Cloud Router) |
| Prefix filtering | ✅ Automatic | N/A | N/A | ✅ Manual |
| Multi-tenant isolation | ✅ Per-VR | N/A | N/A | ✅ Per-VPC |
| MetalLB support | ✅ Yes | ❌ No (use ELB) | ❌ No (use Azure LB) | ✅ Yes |
| BFD support | ✅ Yes | N/A | N/A | ✅ Yes |

**Competitive Advantage:** CloudStack will be **first major IaaS platform** to offer native guest-side BGP for tenant workloads

---

## Documentation Artifacts

### Created Files (This Package)
```
Build/Features/guestBGP/
├── README.md                          # This file (overview)
├── DESIGN_SPECIFICATION.md            # Detailed technical design
├── API_SPECIFICATION.md               # CloudStack API changes
├── SECURITY_MODEL.md                  # Security controls and threat model
├── TESTING_PLAN.md                    # Test cases and validation
├── DEPLOYMENT_GUIDE.md                # Operations and troubleshooting
└── examples/
    ├── kubernetes-metallb.md          # MetalLB integration example
    ├── postgresql-patroni.md          # Database VIP example
    └── anycast-dns.md                 # Multi-zone anycast example
```

---

## Next Steps

1. **Community Feedback (Nov-Dec 2025)**
   - Share design on dev@cloudstack.apache.org
   - Gather feedback from operators and developers
   - Present at CloudStack European User Group

2. **Proof of Concept (Jan 2025)**
   - Manual VR config (simulate feature)
   - Validate BGP session establishment
   - Test prefix filtering and security controls

3. **Implementation (Feb-Jun 2025)**
   - Phase 1: Core functionality (CloudStack 4.22)
   - Phase 2: Security hardening (CloudStack 4.23)
   - Code review and testing

4. **Production Deployment (Q3 2025)**
   - Beta testing with select customers
   - Documentation and training materials
   - CloudStack 4.23 release

---

## References

- **Existing Documentation:** `/Builder2/docs/FUTURE_SCENARIO_VR_GUEST_BGP.md`
- **VNFramework:** `/Builder2/Build/Features/VNFramework/` (related VNF feature)
- **IPv6 Allocation:** `/Builder2/lab/IPv6/DETAILED_IPV6_ALLOCATION.md`
- **Router Configs:** `/Builder2/lab/router-configs/`
- **Presentation:** `/Builder2/presentation/prototype/mock/scenarios.html` (Scenario 5)

---

## Contact

**Author:** Alexandre Mattioli  
**Email:** (via ShapeBlue)  
**GitHub:** @alexandremattioli  
**Organization:** ShapeBlue - The CloudStack Company

**Contributions Welcome!** This is a design document for community review. Feedback, suggestions, and code contributions are encouraged.

---

**License:** Apache 2.0 (same as Apache CloudStack)  
**Status:** Design Phase - Not Yet Implemented  
**Last Updated:** November 20, 2025
