# Guest-Side BGP Peering - Security Model

**Feature:** VR Guest-Side BGP Peering  
**Target Release:** CloudStack 4.23 (Q2 2025)  
**Security Classification:** CRITICAL (Tenant Isolation & Network Security)  
**Author:** Alexandre Mattioli (@alexandremattioli)  
**Date:** November 20, 2025

---

## Executive Summary

Guest-side BGP peering introduces a **trust boundary** between tenant VMs and Virtual Routers. This document defines the **security controls** required to prevent:

1. **Route Hijacking** - Malicious tenant advertising unauthorized prefixes
2. **Denial of Service** - Route table exhaustion, CPU starvation
3. **Lateral Movement** - Cross-tenant routing violations
4. **Information Disclosure** - BGP session snooping, route enumeration

**Security Posture:** Defense-in-Depth (4 control layers)

---

## Threat Model

### Attack Surface

```
┌─────────────────────────────────────────────────────────┐
│ Tenant VM (Attacker)                                    │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ FRR BGP Daemon (Malicious Config)                   │ │
│ │ - Advertises unauthorized prefixes                  │ │
│ │ - Floods route updates                              │ │
│ │ - Probes BGP session state                          │ │
│ └─────────────────────────────────────────────────────┘ │
└───────────────────────────┬─────────────────────────────┘
                            │ BGP Port 179 (IPv6)
                            ▼
┌─────────────────────────────────────────────────────────┐
│ Virtual Router (VR)                                     │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ FRR BGP Daemon (Trust Boundary)                     │ │
│ │ ✓ Prefix validation                                 │ │
│ │ ✓ Rate limiting                                     │ │
│ │ ✓ Session authentication (Phase 2)                  │ │
│ └─────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Linux Kernel Routing Table (Protected)             │ │
│ └─────────────────────────────────────────────────────┘ │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
                  (Upstream BGP to ISPs)
```

### Threat Actors

| Actor | Motivation | Capability |
|-------|-----------|------------|
| **Malicious Tenant** | Route hijacking for MITM attacks | Full control over guest VM BGP config |
| **Compromised VM** | Lateral movement after initial breach | BGP daemon compromise via CVE |
| **Insider Threat** | Domain admin abusing network offering | API access to BGP parameters |

---

## Security Controls

### Layer 1: Prefix Validation (CRITICAL)

**Objective:** Prevent route hijacking by restricting advertised prefixes to authorized ranges

**Implementation:**

FRR configuration on VR:
```
router bgp 65101
  neighbor 2a01:b000:1046:10:1::50 remote-as 65201
  
  address-family ipv6 unicast
    neighbor 2a01:b000:1046:10:1::50 prefix-list TENANT_ALLOW in
  exit-address-family

ipv6 prefix-list TENANT_ALLOW seq 5 permit 2a01:b000:1046:10:1::/64 le 128
ipv6 prefix-list TENANT_ALLOW seq 10 deny any
```

**Control Logic:**
1. **Allowed Range:** Network's IPv6 CIDR block (e.g., `2a01:b000:1046:10:1::/64`)
2. **Prefix Length Constraint:** Network offering defines `min/max` prefix length
   - Default: `/128` only (host routes)
   - Configurable: `/64` to `/128` for subnets
3. **Automatic Rejection:** Routes outside range are **never** installed
4. **Audit Logging:** Rejected routes logged to CloudStack events

**Attack Mitigation:**
- ❌ Tenant advertises `0::/0` (default route) → **REJECTED** (not in allowed range)
- ❌ Tenant advertises `2a01:b000:1046:20:1::100/128` → **REJECTED** (wrong network)
- ✅ Tenant advertises `2a01:b000:1046:10:1::100/128` → **ACCEPTED** (valid)

**CloudStack Validation:**
```sql
-- Pseudo-code for route acceptance check
IF route.prefix NOT IN network.ipv6_cidr THEN
  REJECT route
  INSERT INTO bgp_guest_routes (state='Rejected', reason='Prefix not in allowed range')
END IF
```

---

### Layer 2: Rate Limiting (HIGH)

**Objective:** Prevent DoS via route table exhaustion and UPDATE flooding

**Max-Prefix Limit:**
```
router bgp 65101
  neighbor 2a01:b000:1046:10:1::50 maximum-prefix 10 90 warning-only
```

**Controls:**
- **Default:** 10 routes per VM (network offering configurable)
- **Warning Threshold:** 90% (9 routes) triggers CloudStack alert
- **Action:** `warning-only` in Phase 1 (no auto-shutdown)
  - Phase 2: `maximum-prefix 10` (hard limit, tears down session)

**Rate Limiting (FRR Feature):**
```
router bgp 65101
  neighbor 2a01:b000:1046:10:1::50 update-delay 5
```
- Max 1 UPDATE message per 5 seconds from guest VM
- Prevents CPU starvation on VR

**CloudStack Monitoring:**
```json
{
  "event": "MAX_PREFIX_WARNING",
  "peeringid": "peer-uuid-abc",
  "currentcount": 9,
  "maxallowed": 10,
  "action": "Email sent to tenant admin"
}
```

**Attack Mitigation:**
- ❌ Tenant advertises 100 routes → **LIMITED** (only 10 accepted)
- ❌ Tenant sends 1000 UPDATEs/sec → **THROTTLED** (1 per 5 seconds)

---

### Layer 3: ASN Validation (MEDIUM)

**Objective:** Prevent ASN spoofing and unauthorized peering

**Network Offering Configuration:**
- **Allowed ASN Range:** 65200-65299 (tenant-reserved private ASNs)
- **VR ASN:** 65101 (fixed for all VRs in network)

**FRR Enforcement:**
```
router bgp 65101
  neighbor 2a01:b000:1046:10:1::50 remote-as 65201
  neighbor 2a01:b000:1046:10:1::50 enforce-first-as
```
- `enforce-first-as`: Verifies first ASN in AS_PATH matches remote-as
- Prevents AS_PATH manipulation

**CloudStack Validation:**
1. **Session Initialization:**
   - Guest VM sends BGP OPEN with ASN
   - VR checks ASN against allowed range (65200-65299)
   - If outside range → **REJECT** connection
2. **Database Enforcement:**
```sql
-- Constraint on bgp_guest_peering table
CONSTRAINT chk_guest_asn 
  CHECK (guest_asn BETWEEN 65200 AND 65299)
```

**Attack Mitigation:**
- ❌ Tenant uses ASN 64512 (common private ASN) → **REJECTED**
- ❌ Tenant uses ASN 13335 (Cloudflare) → **REJECTED**
- ✅ Tenant uses ASN 65201 → **ACCEPTED**

---

### Layer 4: Session Authentication (Phase 2)

**Objective:** Prevent session hijacking and MITM attacks

**MD5 Authentication (TCP-MD5):**
```
router bgp 65101
  neighbor 2a01:b000:1046:10:1::50 password SECRET_PASSWORD
```

**Implementation Plan:**
- **Phase 1 (MVP):** No authentication (passive listening)
- **Phase 2 (CloudStack 4.24):** MD5 password per session
  - Password auto-generated by CloudStack
  - Delivered to tenant via metadata service
  - Rotated every 90 days

**API Extension (Phase 2):**
```bash
cloudmonkey configure bgp guest authentication \
  peeringid=<peer-id> \
  password=<auto-generated-secret>
```

**Attack Mitigation (Phase 2):**
- ❌ Attacker on same L2 segment spoofs BGP OPEN → **REJECTED** (wrong password)
- ❌ Replay attack with captured packets → **REJECTED** (TCP sequence numbers)

---

## Isolation Guarantees

### Tenant Isolation

**Scenario:** Two tenants in same CloudStack zone

```
Tenant A Network (2a01:b000:1046:10:1::/64)
- VM1: 2a01:b000:1046:10:1::50 (ASN 65201)

Tenant B Network (2a01:b000:1046:20:1::/64)
- VM2: 2a01:b000:1046:20:1::60 (ASN 65202)
```

**Isolation Controls:**
1. **Separate VRs:** Each network has dedicated VR
2. **Separate BGP Sessions:** VR-A only peers with Tenant A VMs
3. **Prefix Isolation:** VR-A rejects prefixes from Tenant B's CIDR
4. **Routing Isolation:** VR-A kernel routing table isolated from VR-B

**Attack Scenario:**
- Tenant A tries to advertise Tenant B's prefix (`2a01:b000:1046:20:1::100/128`)
- VR-A rejects: Prefix not in allowed range (`2a01:b000:1046:10:1::/64`)
- **Result:** ✅ Isolation maintained

---

### Network Isolation (VLANs)

**VLAN Segmentation:**
```
┌─────────────────────────────────────────┐
│ Tenant A Network (VLAN 100)            │
│ VR-A (BGP only listens on VLAN 100)    │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Tenant B Network (VLAN 200)            │
│ VR-B (BGP only listens on VLAN 200)    │
└─────────────────────────────────────────┘
```

**Enforcement:**
- VR listens on `link-local` IPv6 address of guest network interface
- FRR binds to specific interface: `listen-on eth1`
- BGP packets on wrong VLAN are dropped by hypervisor

---

## Audit & Compliance

### Logging Requirements

**BGP Events Logged:**
1. **Session State Changes:**
   - `SESSION_ESTABLISHED` (peer IP, ASN, timestamp)
   - `SESSION_DOWN` (reason, duration)
2. **Route Rejections:**
   - `ROUTE_REJECTED` (prefix, reason: "not in allowed range")
   - `MAX_PREFIX_VIOLATION` (current count, max allowed)
3. **Administrative Actions:**
   - `SESSION_RESET` (admin user, reason)
   - `CONFIG_UPDATED` (parameter changed, old/new values)

**Log Destination:**
- CloudStack Management Server database: `bgp_guest_peering_events` table
- VR syslog: `/var/log/cloudstack/bgp.log`
- Optional: Forward to SIEM (Splunk, ELK)

**Retention:**
- Database events: 90 days (configurable)
- VR logs: 7 days (rotated daily)

---

### Compliance Controls

**PCI-DSS Alignment:**
- **Requirement 1.2.1:** Restrict inbound/outbound traffic
  - ✅ Prefix validation enforces allowed ranges
- **Requirement 10.2:** Audit logging for network changes
  - ✅ All BGP events logged to CloudStack

**GDPR Considerations:**
- **Data Minimization:** Only log IP addresses, ASNs (no personal data)
- **Data Retention:** Auto-delete events after 90 days

---

## Security Testing

### Penetration Testing Scenarios

**Test 1: Route Hijacking Attempt**
- **Setup:** Deploy VM in network A, configure BGP to advertise network B's prefix
- **Expected:** VR rejects route, logs `ROUTE_REJECTED` event
- **Validation:** Check `bgp_guest_routes` table for rejected routes

**Test 2: DoS via Route Flooding**
- **Setup:** Configure guest BGP to advertise 1000 prefixes
- **Expected:** VR accepts first 10 routes, rejects rest, logs `MAX_PREFIX_VIOLATION`
- **Validation:** Check VR CPU usage remains <50%, routing table size ≤ 10

**Test 3: ASN Spoofing**
- **Setup:** Configure guest BGP with ASN outside allowed range (e.g., 64512)
- **Expected:** VR refuses BGP session, no peering established
- **Validation:** Check `bgp_guest_peering` table shows state = "Idle"

**Test 4: Cross-Tenant Route Injection**
- **Setup:** VM in network A advertises prefix from network B
- **Expected:** VR rejects route, isolation maintained
- **Validation:** Check VR routing table shows only network A prefixes

---

### Automated Security Tests

**Unit Tests:**
```python
# Test: Prefix validation logic
def test_prefix_validation():
    allowed_range = ipaddress.IPv6Network("2a01:b000:1046:10:1::/64")
    test_prefix = ipaddress.IPv6Network("2a01:b000:1046:20:1::100/128")
    
    assert is_prefix_allowed(test_prefix, allowed_range) == False
    
# Test: ASN range validation
def test_asn_validation():
    assert is_asn_allowed(65201, min=65200, max=65299) == True
    assert is_asn_allowed(64512, min=65200, max=65299) == False
```

**Integration Tests:**
```bash
# Test: FRR prefix-list enforcement
vtysh -c 'show bgp ipv6 unicast neighbors 2a01:b000:1046:10:1::50 routes'
# Expected: Only routes matching prefix-list TENANT_ALLOW

# Test: Max-prefix enforcement
vtysh -c 'show bgp ipv6 unicast summary' | grep '2a01:b000:1046:10:1::50'
# Expected: "PfxRcd" column shows ≤ 10
```

---

## Incident Response

### Security Incidents

**Incident 1: Malicious Route Advertisement Detected**

**Detection:**
```sql
SELECT * FROM bgp_guest_peering_events
WHERE eventtype = 'ROUTE_REJECTED'
AND message LIKE '%not in allowed range%'
ORDER BY timestamp DESC
LIMIT 10;
```

**Response:**
1. **Isolate:** Quarantine VM (suspend instance)
2. **Investigate:** Check VM logs, BGP config, running processes
3. **Remediate:** Rebuild VM from clean template, rotate credentials
4. **Notify:** Email tenant admin with incident details

---

**Incident 2: Max-Prefix Violation (Potential DoS)**

**Detection:**
```sql
SELECT * FROM bgp_guest_peering_events
WHERE eventtype = 'MAX_PREFIX_VIOLATION'
AND timestamp > NOW() - INTERVAL 1 HOUR;
```

**Response:**
1. **Alert:** Send email to tenant admin + CloudStack operator
2. **Throttle:** Reduce max-prefix limit to 5 (temporary)
3. **Analyze:** Determine if legitimate (e.g., K8s autoscaling) or malicious
4. **Resolve:** Adjust limit or block session

---

## Security Roadmap

### Phase 1 (MVP - CloudStack 4.23)
- ✅ Prefix validation
- ✅ Rate limiting (max-prefix)
- ✅ ASN validation
- ✅ Audit logging

### Phase 2 (CloudStack 4.24)
- [ ] MD5 authentication
- [ ] BGP FlowSpec (DDoS mitigation)
- [ ] Prefix filtering API (custom filters)

### Phase 3 (CloudStack 4.25+)
- [ ] BMP (BGP Monitoring Protocol) integration
- [ ] RPKI validation (ROV)
- [ ] BGP-LS (Link-State) for topology visibility

---

## Security Review Checklist

**Pre-Release Validation:**
- [ ] Penetration test: Route hijacking attempts
- [ ] Penetration test: DoS via route flooding
- [ ] Code review: Prefix validation logic
- [ ] Code review: Database input sanitization (SQL injection)
- [ ] Audit: Logging covers all security events
- [ ] Compliance: PCI-DSS requirements met
- [ ] Documentation: Security best practices published

**Operational Security:**
- [ ] Monitoring: Alerts for rejected routes
- [ ] Monitoring: Alerts for max-prefix violations
- [ ] Incident Response: Runbook created
- [ ] Training: CloudStack admins trained on BGP security

---

## References

- **NIST SP 800-54:** Border Gateway Protocol Security
- **RFC 7454:** BGP Operations and Security
- **MANRS (Mutually Agreed Norms for Routing Security):** https://www.manrs.org/
- **FRR Security Hardening:** https://docs.frrouting.org/en/latest/security.html
- **CloudStack Security Guide:** https://docs.cloudstack.apache.org/

---

**Status:** Security Model Complete - Ready for Review  
**Security Classification:** CRITICAL (Network Isolation & Routing Security)  
**Next Steps:** Security audit + penetration testing  
**Last Updated:** November 20, 2025
