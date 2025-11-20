# Guest-Side BGP Peering - Implementation Plan

**Feature:** VR Guest-Side BGP Peering  
**Target Release:** CloudStack 4.23 (Q2 2025)  
**Project Code:** CLOUDSTACK-GUESTBGP  
**Author:** Alexandre Mattioli (@alexandremattioli)  
**Date:** November 20, 2025

---

## Executive Summary

This document outlines the **phased implementation roadmap** for native guest-side BGP peering in Apache CloudStack. The plan balances:

- **MVP Speed:** Get core functionality to users by CloudStack 4.23 (Q2 2025)
- **Security First:** All security controls in Phase 1 (no deferring critical features)
- **Backward Compatibility:** No breaking changes to existing deployments

**Total Effort:** ~12 weeks (3 phases)

---

## Implementation Phases

### Phase 1: MVP - Core Functionality (CloudStack 4.23)

**Timeline:** 8 weeks (Q1 2025)  
**Goal:** Enable tenant VMs to peer with VR and advertise routes

**Deliverables:**

1. **Database Schema Changes** (Week 1)
   - Create `bgp_guest_peering` table
   - Create `bgp_guest_routes` table
   - Create `bgp_guest_peering_events` table
   - Add columns to `network_offerings` table
   - Migration scripts for upgrading CloudStack 4.22 → 4.23

2. **Network Offering API Extensions** (Week 1)
   - Extend `updateNetworkOffering` API with 6 new parameters
   - Add validation logic (ASN range, prefix length constraints)
   - Update API documentation

3. **VR FRR Configuration** (Week 2-3)
   - Implement FRR bgpd.conf Jinja2 template
   - Add prefix-list generation logic
   - Implement max-prefix configuration
   - Add ASN validation
   - Create VR agent script to apply config

4. **BGP Session Detection** (Week 3-4)
   - VR agent: Poll FRR every 60 seconds
   - Parse `show bgp ipv6 unicast summary json`
   - Detect new sessions, update CloudStack DB
   - Implement session state machine (Idle → Connect → Established)

5. **Route Acceptance Logic** (Week 4-5)
   - VR agent: Poll FRR for received routes
   - Parse `show bgp ipv6 unicast neighbors <ip> routes json`
   - Validate routes against prefix-list
   - Insert accepted/rejected routes into `bgp_guest_routes` table
   - Automatic redistribution to upstream BGP (ISP peering)

6. **CloudStack Management Server APIs** (Week 5-6)
   - Implement `listBgpGuestPeeringSessions` API
   - Implement `listBgpGuestRoutes` API
   - Implement `getBgpGuestPeeringMetrics` API
   - Implement `listBgpGuestPeeringEvents` API
   - Add permission checks (RBAC)

7. **UI Changes (CloudStack Web UI)** (Week 6-7)
   - Add "Guest BGP" tab to Network Offering creation/edit
   - Add "BGP Sessions" view to Network details page
   - Add "BGP Routes" view with filtering
   - Add "BGP Events" audit log view

8. **Testing** (Week 7-8)
   - Unit tests for API validation logic
   - Integration tests with live FRR instances
   - Performance tests (100 sessions, 1000 routes)
   - Security tests (route hijacking, DoS)
   - End-to-end test: Kubernetes MetalLB demo

**Phase 1 Dependencies:**
- CloudStack 4.22 baseline code
- FRR 8.5+ package in VR template
- IPv6-enabled network infrastructure

**Phase 1 Exit Criteria:**
- ✅ MVP feature complete (passive BGP, prefix validation, rate limiting)
- ✅ All security controls implemented
- ✅ Documentation published (README, API spec, security model)
- ✅ Example configurations available (K8s, PostgreSQL)
- ✅ Pass all security penetration tests

---

### Phase 2: Hardening & Advanced Features (CloudStack 4.24)

**Timeline:** 3 weeks (Q3 2025)  
**Goal:** Production-grade security and operational features

**Deliverables:**

1. **BGP Authentication** (Week 1)
   - MD5 password generation in CloudStack
   - FRR config: `neighbor <ip> password <secret>`
   - API: `configureBgpGuestAuthentication`
   - Metadata service integration (deliver password to VM)

2. **IPv4 Support** (Week 1-2)
   - Extend schema to support dual-stack (IPv4 + IPv6)
   - Add IPv4 prefix-list generation
   - FRR config: `address-family ipv4 unicast`
   - API: Support both `ipv4routes` and `ipv6routes`

3. **Advanced Rate Limiting** (Week 2)
   - Hard max-prefix limits (tear down session)
   - UPDATE message rate limiting
   - Configurable thresholds per network offering

4. **VRRP Integration** (Week 2-3)
   - Redundant VR support (active-active BGP)
   - Shared VRRP VIP for BGP peering
   - FRR config: Anycast BGP on VRRP IP

5. **Administrative Tools** (Week 3)
   - API: `resetBgpGuestPeeringSession`
   - API: `updateBgpGuestPeeringConfig`
   - API: `deleteBgpGuestPeeringSession`
   - Web UI: Manual session reset button

**Phase 2 Exit Criteria:**
- ✅ BGP authentication enabled and tested
- ✅ IPv4 support validated
- ✅ VRRP + BGP tested with redundant VRs
- ✅ Admin tools operational

---

### Phase 3: Observability & Advanced Routing (CloudStack 4.25)

**Timeline:** 1 week (Q4 2025)  
**Goal:** Production monitoring and advanced BGP features

**Deliverables:**

1. **Prometheus Metrics** (Week 1)
   - Export BGP session metrics (uptime, prefix count)
   - Export route acceptance rate (rejected/accepted ratio)
   - CloudStack exporter endpoint: `/metrics/bgp`

2. **BGP Communities** (Week 1)
   - Network offering: Allow community configuration
   - FRR config: `neighbor <ip> send-community`
   - Use case: Traffic engineering hints to ISP

3. **BMP (BGP Monitoring Protocol)** (Week 1)
   - Real-time BGP update streaming
   - Integration with monitoring platforms (Grafana)

**Phase 3 Exit Criteria:**
- ✅ Prometheus metrics available
- ✅ BGP communities supported
- ✅ BMP integration complete

---

## Development Milestones

### Milestone 1: Database Schema Complete (Week 1)

**Tasks:**
- [ ] Write SQL migration scripts
- [ ] Test schema upgrade from CloudStack 4.22
- [ ] Validate foreign key constraints
- [ ] Add database indexes for performance

**Acceptance Criteria:**
- Schema migration runs cleanly on test environment
- No data loss from existing deployments
- Queries perform within 100ms (indexed lookups)

---

### Milestone 2: VR FRR Configuration (Week 3)

**Tasks:**
- [ ] Implement Jinja2 template for bgpd.conf
- [ ] Add template variables for ASN, prefix-list, max-prefix
- [ ] Test template rendering with various inputs
- [ ] Deploy to test VR, validate FRR parses config

**Acceptance Criteria:**
- FRR accepts generated config without errors
- BGP session establishes with test VM
- Prefix-list correctly rejects out-of-range routes

**Example Template Output:**
```
router bgp 65101
  neighbor 2a01:b000:1046:10:1::50 remote-as 65201
  neighbor 2a01:b000:1046:10:1::50 passive
  neighbor 2a01:b000:1046:10:1::50 maximum-prefix 10 90 warning-only
  
  address-family ipv6 unicast
    neighbor 2a01:b000:1046:10:1::50 prefix-list TENANT_ALLOW in
  exit-address-family

ipv6 prefix-list TENANT_ALLOW seq 5 permit 2a01:b000:1046:10:1::/64 le 128
ipv6 prefix-list TENANT_ALLOW seq 10 deny any
```

---

### Milestone 3: API Implementation Complete (Week 6)

**Tasks:**
- [ ] Implement all 8 CloudStack APIs
- [ ] Add API unit tests (mocked DB)
- [ ] Add permission checks (Root Admin, Domain Admin, User)
- [ ] Generate API documentation (Swagger)

**Acceptance Criteria:**
- All APIs callable via `cloudmonkey`
- API responses match schema in API_SPECIFICATION.md
- RBAC enforced (users can only list own sessions)

**Test Example:**
```bash
# As tenant user
cloudmonkey list bgp guest peering sessions
# Expected: Only sees own VMs' sessions

# As root admin
cloudmonkey list bgp guest peering sessions
# Expected: Sees all sessions across all tenants
```

---

### Milestone 4: End-to-End Demo (Week 8)

**Tasks:**
- [ ] Deploy Kubernetes cluster in CloudStack network
- [ ] Configure MetalLB with guest BGP
- [ ] Advertise LoadBalancer IP via BGP
- [ ] Verify external connectivity to service
- [ ] Document demo steps

**Demo Scenario:**
```
1. Create CloudStack network with guest BGP enabled
2. Deploy 3-node Kubernetes cluster
3. Install MetalLB with BGP mode
4. Deploy nginx service with LoadBalancer type
5. MetalLB advertises 2a01:b000:1046:10:1::100/128 via BGP
6. VR accepts route, redistributes to ISP
7. External client curls http://[2a01:b000:1046:10:1::100]
8. ✅ Success: nginx responds
```

**Acceptance Criteria:**
- External connectivity works
- CloudStack UI shows session as "Established"
- Route visible in `listBgpGuestRoutes` API
- No security violations (prefix validation working)

---

## Code Structure

### Repository Layout

```
cloudstack/
├── api/
│   └── src/com/cloud/network/bgp/
│       ├── BgpGuestPeering.java           # Entity interface
│       ├── BgpGuestRoute.java             # Route entity
│       └── BgpGuestPeeringService.java    # Service interface
│
├── engine/
│   └── orchestration/
│       └── BgpGuestPeeringOrchestrator.java  # Core orchestration
│
├── server/
│   ├── src/com/cloud/network/bgp/
│   │   ├── BgpGuestPeeringManagerImpl.java   # Service implementation
│   │   ├── BgpGuestPeeringDao.java           # Database DAO
│   │   └── BgpGuestPeeringValidation.java    # Input validation
│   │
│   └── test/com/cloud/network/bgp/
│       ├── BgpGuestPeeringTest.java          # Unit tests
│       └── BgpGuestPeeringIntegrationTest.java
│
├── systemvm/
│   └── debian/opt/cloud/bin/
│       ├── bgp_monitor.py                    # VR agent (polls FRR)
│       └── bgp_config_generator.py           # FRR config generator
│
├── ui/
│   └── modules/network/
│       └── bgp/
│           ├── BgpSessionsList.vue           # Vue component
│           ├── BgpRoutesView.vue
│           └── BgpEventsLog.vue
│
└── setup/
    └── db/
        └── db/schema-4.23.0.sql              # Schema migration
```

---

### Key Components

**1. BgpGuestPeeringManagerImpl.java**

**Responsibilities:**
- Implement CloudStack API logic
- Validate input parameters (ASN range, prefix length)
- Query database via DAO
- Trigger VR configuration updates

**Key Methods:**
```java
public class BgpGuestPeeringManagerImpl implements BgpGuestPeeringService {
    
    @Override
    public List<BgpGuestPeering> listBgpGuestPeeringSessions(
        Long networkId, 
        Long vmId, 
        String state
    ) {
        // Query database with filters
        // Apply RBAC (user can only see own VMs)
        // Return list of sessions
    }
    
    @Override
    public BgpGuestRoute acceptRoute(
        Long peeringId, 
        String prefix
    ) {
        // Validate prefix against network CIDR
        // Check prefix length constraints
        // Update database (state = Accepted)
        // Trigger VR route redistribution
    }
}
```

---

**2. bgp_monitor.py (VR Agent)**

**Responsibilities:**
- Poll FRR every 60 seconds
- Detect new BGP sessions
- Report route updates to CloudStack Management Server
- Handle FRR errors

**Pseudo-code:**
```python
#!/usr/bin/env python3
import json
import subprocess
import requests

CLOUDSTACK_API = "http://management-server/api"
POLL_INTERVAL = 60  # seconds

def get_bgp_sessions():
    """Query FRR for BGP sessions"""
    cmd = "vtysh -c 'show bgp ipv6 unicast summary json'"
    result = subprocess.run(cmd, shell=True, capture_output=True)
    return json.loads(result.stdout)

def report_session_to_cloudstack(session):
    """Send session data to CloudStack API"""
    data = {
        "command": "reportBgpGuestPeeringSession",
        "guestip": session['peer'],
        "guestasn": session['remoteAs'],
        "state": session['state'],
        "prefixcount": session['prefixReceivedCount']
    }
    requests.post(CLOUDSTACK_API, data=data)

if __name__ == "__main__":
    while True:
        sessions = get_bgp_sessions()
        for peer, session in sessions['ipv6Unicast']['peers'].items():
            report_session_to_cloudstack(session)
        time.sleep(POLL_INTERVAL)
```

---

**3. bgp_config_generator.py**

**Responsibilities:**
- Receive network offering config from CloudStack
- Generate FRR bgpd.conf from Jinja2 template
- Reload FRR daemon

**Pseudo-code:**
```python
from jinja2 import Template

TEMPLATE = """
router bgp {{ vr_asn }}
  {% for peer in peers %}
  neighbor {{ peer.ip }} remote-as {{ peer.asn }}
  neighbor {{ peer.ip }} passive
  neighbor {{ peer.ip }} maximum-prefix {{ peer.max_prefix }} 90 warning-only
  
  address-family ipv6 unicast
    neighbor {{ peer.ip }} prefix-list TENANT_{{ peer.asn }}_ALLOW in
  exit-address-family
  {% endfor %}

{% for peer in peers %}
ipv6 prefix-list TENANT_{{ peer.asn }}_ALLOW seq 5 permit {{ peer.allowed_range }} le {{ peer.max_prefix_length }}
ipv6 prefix-list TENANT_{{ peer.asn }}_ALLOW seq 10 deny any
{% endfor %}
"""

def generate_config(network_offering, guest_vms):
    peers = []
    for vm in guest_vms:
        peers.append({
            'ip': vm.ipv6,
            'asn': vm.asn,
            'max_prefix': network_offering.max_prefixes,
            'allowed_range': network_offering.ipv6_cidr,
            'max_prefix_length': network_offering.max_prefix_length
        })
    
    template = Template(TEMPLATE)
    config = template.render(vr_asn=65101, peers=peers)
    
    with open('/etc/frr/bgpd.conf', 'w') as f:
        f.write(config)
    
    subprocess.run(['systemctl', 'reload', 'frr'])
```

---

## Testing Strategy

### Unit Tests

**Coverage:** 80% minimum

**Test Classes:**
- `BgpGuestPeeringValidationTest` - Input validation logic
- `BgpGuestPeeringDaoTest` - Database CRUD operations
- `BgpPrefixValidationTest` - Prefix range checking
- `BgpAsnValidationTest` - ASN range checking

**Example Test:**
```java
@Test
public void testPrefixValidation_RejectOutOfRange() {
    String allowedRange = "2a01:b000:1046:10:1::/64";
    String testPrefix = "2a01:b000:1046:20:1::100/128";
    
    boolean result = BgpPrefixValidator.isAllowed(testPrefix, allowedRange);
    
    assertFalse(result);
}
```

---

### Integration Tests

**Test Environment:**
- CloudStack 4.23 test deployment
- 1 VR with FRR 8.5
- 2 test VMs with FRR configured as guests

**Test Scenarios:**

1. **Session Establishment:**
   - Start test VM with BGP enabled
   - Wait for session to reach "Established" state
   - Verify CloudStack DB shows session

2. **Route Advertisement:**
   - Test VM advertises `2a01:b000:1046:10:1::100/128`
   - Verify VR accepts route
   - Verify CloudStack API shows route as "Accepted"

3. **Prefix Rejection:**
   - Test VM advertises `2a01:b000:1046:20:1::100/128` (wrong network)
   - Verify VR rejects route
   - Verify CloudStack logs rejection event

4. **Max-Prefix Enforcement:**
   - Test VM advertises 15 routes (exceeds limit of 10)
   - Verify VR accepts first 10, rejects rest
   - Verify CloudStack logs MAX_PREFIX_VIOLATION event

---

### Performance Tests

**Load Test:**
- 100 VMs per network
- Each VM peers with VR
- Each VM advertises 10 routes
- Total: 100 sessions, 1000 routes

**Metrics:**
- VR CPU usage: < 50%
- VR memory usage: < 512 MB
- Route convergence time: < 5 seconds
- API response time: < 200ms

**Tools:**
- Apache JMeter for API load testing
- FRR stress test scripts
- CloudStack monitoring (Prometheus)

---

### Security Tests

**Penetration Testing:**

1. **Route Hijacking:**
   - Attempt to advertise `0::/0` default route
   - Attempt to advertise public IPv6 ranges
   - **Expected:** All rejected, logged

2. **DoS via Flooding:**
   - Send 1000 BGP UPDATE messages/second
   - **Expected:** Rate limiting kicks in, VR CPU < 80%

3. **Cross-Tenant Attack:**
   - VM in network A tries to advertise network B's prefix
   - **Expected:** Rejected by prefix-list

**Tools:**
- Custom BGP fuzzing scripts
- Scapy (packet crafting)
- Manual penetration testing

---

## Migration & Rollback

### Upgrading from CloudStack 4.22

**Migration Steps:**

1. **Database Schema Upgrade:**
   ```bash
   mysql -u cloud -p cloud < /usr/share/cloudstack-management/setup/db/schema-4.23.0.sql
   ```
   - Creates 3 new tables
   - Adds columns to `network_offerings`

2. **VR Template Upgrade:**
   - Deploy new VR template with FRR 8.5+
   - CloudStack auto-migrates networks to new VR template
   - No downtime for existing VMs

3. **Feature Enablement:**
   - Guest BGP disabled by default
   - Admins must update network offerings to enable

**Backward Compatibility:**
- Existing networks without guest BGP: No changes
- Existing APIs: Unchanged
- VR without FRR: Continues to work (no BGP functionality)

---

### Rollback Plan

**Scenario:** Critical bug found in CloudStack 4.23

**Rollback Steps:**

1. **Disable Guest BGP:**
   ```bash
   cloudmonkey update networkoffering id=<id> guestbgppeeringenabled=false
   ```

2. **Downgrade CloudStack:**
   ```bash
   apt-get install cloudstack-management=4.22.0
   systemctl restart cloudstack-management
   ```

3. **Database Rollback:**
   ```sql
   -- Drop new tables
   DROP TABLE IF EXISTS bgp_guest_peering_events;
   DROP TABLE IF EXISTS bgp_guest_routes;
   DROP TABLE IF EXISTS bgp_guest_peering;
   
   -- Remove columns from network_offerings
   ALTER TABLE network_offerings DROP COLUMN guest_bgp_peering_enabled;
   -- ... (remove other columns)
   ```

**Data Loss:**
- BGP session history lost
- Route history lost
- Network offering BGP config lost
- No impact on VMs or routing (BGP sessions stop cleanly)

---

## Documentation Plan

### User Documentation

**1. Administrator Guide:**
- **Title:** "Enabling Guest-Side BGP Peering"
- **Sections:**
  - Network offering configuration
  - Security considerations
  - Troubleshooting common issues
- **Format:** Markdown + screenshots
- **Location:** `/docs/adminguide/guest-bgp.md`

**2. API Reference:**
- **Generated from:** Swagger annotations in Java code
- **Hosted at:** https://cloudstack.apache.org/api/4.23.0/
- **Includes:** Request/response examples, error codes

**3. Tenant Guide:**
- **Title:** "Using BGP in Your CloudStack Network"
- **Sections:**
  - How to configure FRR on guest VMs
  - Example: Kubernetes MetalLB setup
  - Example: PostgreSQL Patroni with BGP VIPs
- **Format:** Step-by-step tutorial
- **Location:** `/docs/userguide/guest-bgp-tutorial.md`

---

### Developer Documentation

**1. Architecture Overview:**
- Component diagram
- Sequence diagrams (session establishment, route advertisement)
- Database ER diagram

**2. Code Walkthrough:**
- Key classes and interfaces
- Extension points for plugins

**3. Testing Guide:**
- How to run unit tests
- How to set up integration test environment

---

## Risk Management

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| FRR performance issues at scale | Medium | High | Performance testing with 100 sessions, optimize polling |
| Database bottleneck (frequent updates) | Low | Medium | Index optimization, batch inserts |
| VR upgrade breaks existing deployments | Low | Critical | Comprehensive integration tests, gradual rollout |

---

### Security Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Route hijacking not fully prevented | Low | Critical | Penetration testing, security audit |
| DoS via BGP flooding | Medium | High | Rate limiting, max-prefix hard limits |
| SQL injection in API | Low | Critical | Input validation, parameterized queries |

---

### Project Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Timeline slips beyond Q2 2025 | Medium | Medium | Bi-weekly progress reviews, reduce scope if needed |
| Lack of FRR expertise in team | High | Medium | Training, consult FRR community |
| Incomplete documentation | Medium | Medium | Documentation sprints in parallel with development |

---

## Success Metrics

### Adoption Metrics (6 months post-release)

- **Target:** 50+ production deployments using guest BGP
- **Target:** 500+ BGP sessions active across all CloudStack instances
- **Target:** 10+ community blog posts / tutorials

### Performance Metrics

- **Target:** 99.9% session uptime
- **Target:** <5 second route convergence
- **Target:** <200ms API response time (p95)

### Security Metrics

- **Target:** 0 security incidents (route hijacking, DoS)
- **Target:** 100% of rejected routes logged
- **Target:** Pass external security audit

---

## Team & Resources

### Development Team

| Role | Responsibility | Time Commitment |
|------|---------------|-----------------|
| **Backend Engineer (2)** | API, database, orchestration | 8 weeks full-time |
| **SystemVM Engineer (1)** | VR agent, FRR integration | 8 weeks full-time |
| **Frontend Engineer (1)** | Web UI (Vue.js) | 4 weeks full-time |
| **QA Engineer (1)** | Testing, automation | 8 weeks full-time |
| **Security Engineer (1)** | Penetration testing, audit | 2 weeks full-time |
| **Technical Writer (1)** | Documentation | 4 weeks part-time |

### Infrastructure Requirements

- **Test Environment:**
  - 1 CloudStack management server (4 vCPU, 16 GB RAM)
  - 2 KVM hosts (8 vCPU, 32 GB RAM each)
  - 1 upstream router (for BGP testing)
  
- **CI/CD:**
  - Jenkins pipelines for automated testing
  - GitHub Actions for PR validation

---

## Delivery Schedule

### Phase 1 (MVP)

| Week | Milestone | Deliverables |
|------|-----------|-------------|
| 1 | Database schema complete | SQL scripts, migration tested |
| 2 | VR FRR config generator | Jinja2 templates, test configs |
| 3 | VR agent (BGP monitoring) | Python script, session detection |
| 4 | Route validation logic | Prefix filtering, max-prefix |
| 5 | CloudStack APIs implemented | 8 APIs operational |
| 6 | Web UI complete | Vue components deployed |
| 7 | End-to-end testing | K8s MetalLB demo working |
| 8 | Security testing + docs | Pen test passed, docs published |

**Target Release Date:** April 30, 2025 (CloudStack 4.23 RC1)

---

### Phase 2 (Hardening)

| Week | Milestone | Deliverables |
|------|-----------|-------------|
| 9 | BGP authentication | MD5 passwords, metadata integration |
| 10 | IPv4 support | Dual-stack BGP validated |
| 11 | VRRP integration | Redundant VR + BGP tested |

**Target Release Date:** September 30, 2025 (CloudStack 4.24 RC1)

---

### Phase 3 (Observability)

| Week | Milestone | Deliverables |
|------|-----------|-------------|
| 12 | Prometheus metrics + BMP | Real-time monitoring operational |

**Target Release Date:** December 31, 2025 (CloudStack 4.25 RC1)

---

## Post-Release Support

### Maintenance Plan

**Bug Fixes:**
- Critical bugs: Hotfix within 48 hours
- Major bugs: Patch within 2 weeks
- Minor bugs: Next minor release

**Community Support:**
- Monitor CloudStack mailing lists for guest BGP questions
- Weekly office hours for Q&A
- GitHub issue triage (daily)

**Documentation Updates:**
- Quarterly review of docs based on user feedback
- Video tutorials (YouTube)

---

## Lessons Learned (Post-Mortem)

**To be filled after Phase 1 completion:**

- What went well?
- What could be improved?
- Unexpected challenges?
- Community feedback?

---

## References

- **Feature Overview:** `/Builder2/Build/Features/guestBGP/README.md`
- **Technical Design:** `/Builder2/Build/Features/guestBGP/DESIGN_SPECIFICATION.md`
- **API Specification:** `/Builder2/Build/Features/guestBGP/API_SPECIFICATION.md`
- **Security Model:** `/Builder2/Build/Features/guestBGP/SECURITY_MODEL.md`
- **CloudStack Development Guide:** https://cloudstack.apache.org/developers.html
- **FRR Documentation:** https://docs.frrouting.org/

---

**Status:** Implementation Plan Complete - Ready for Development  
**Next Steps:** Assign development team, kickoff meeting  
**Last Updated:** November 20, 2025
