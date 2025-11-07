# VNF Framework Charter

## Problem Statement

CloudStack lacks native support for Virtual Network Functions (VNFs) - specialized network appliances (firewalls, load balancers, NAT gateways) that run as VMs within guest networks. Current workarounds require:
- Manual API calls to VNF vendor management interfaces
- No CloudStack-native rule management or state tracking
- Operators must maintain separate inventory of VNF instances
- No automated reconciliation between CloudStack network state and VNF configuration
- Network dictionary templates stored outside CloudStack with no versioning

This forces operators to build custom integration glue, creates operational complexity, and prevents CloudStack from being a complete SDN solution for VNF-based networks.

## Scope

**In Scope:**
- VNF appliance lifecycle: deploy, track, health monitoring
- Network dictionary upload/storage: YAML-based VNF API templates
- Firewall rule management: create, update, delete, list via VNF broker
- NAT rule management: SNAT/DNAT operations via VNF broker
- Network reconciliation: sync CloudStack rules with VNF appliance state
- Connectivity testing: validate VNF broker reachability
- Operation tracking: audit log of all VNF API calls with idempotency
- VNF broker abstraction: HTTP client with retry/timeout/auth

**Out of Scope (Phase 1):**
- Load balancer rules (future phase)
- VPN configuration (future phase)
- Multi-vendor VNF discovery/auto-configuration
- VNF appliance provisioning (assumes VM already exists)
- HA/failover of VNF appliances
- Performance metrics collection from VNFs

## Constraints

**Technical:**
- Must integrate with existing CloudStack network service framework
- VNF broker is external HTTP service (Python/Flask), not part of CloudStack
- Dictionary parsing must handle vendor-specific YAML schemas
- Idempotency required (duplicate requests must not create duplicate rules)
- Must work with CloudStack 4.21.x architecture

**Operational:**
- No changes to existing network provider behavior
- Must support rollback if VNF operations fail
- Audit trail required for compliance
- Operations must timeout within 30 seconds

**Resource:**
- Phase 1 implementation: 2-3 weeks
- No additional infrastructure beyond VNF broker VM
- Must reuse CloudStack DB connection pooling

## Dependencies

**External Systems:**
- VNF Broker service (Python Flask app) - provides HTTP API for VNF operations
- VNF appliance VMs (vendor-provided images) - actual network function devices
- Network dictionaries (YAML files) - vendor-specific API mappings

**CloudStack Components:**
- Network service framework (NetworkElement, NetworkProvider)
- Database schema upgrade system
- API command framework
- ConfigKey system for settings

## Success Criteria

### Functional Requirements (Must Have)

1. **Dictionary Management:**
   - Upload YAML dictionary → stored in DB with UUID
   - Associate dictionary with template or network
   - Parse and validate YAML structure
   - List dictionaries by account/template/network

2. **Firewall Rule Operations:**
   - Create rule → VNF broker call → operation record → response with vendor ref
   - Update rule → validate exists → broker call → update operation
   - Delete rule → validate exists → broker call → mark removed
   - List rules → query operations by VNF instance/network
   - Idempotency: duplicate create with same ruleId returns existing operation

3. **Connectivity Testing:**
   - Test VNF appliance → HTTP call to broker → health status
   - Return: reachable (true/false), latency, last contact timestamp

4. **Network Reconciliation:**
   - Compare CloudStack rule state vs VNF appliance state
   - Return: missing rules, extra rules, mismatched rules
   - Provide reconciliation actions (add/remove/update)

5. **Operation Tracking:**
   - Every VNF API call → operation record (pending → in-progress → completed/failed)
   - Store: request payload, response payload, vendor ref, timestamps, error codes
   - Query operations by: VNF instance, state, time range

### Non-Functional Requirements

6. **Performance:**
   - API response time: p95 < 2 seconds (excluding VNF broker latency)
   - Dictionary parsing: < 500ms for typical YAML (< 50KB)
   - DB queries: indexed on vnf_instance_id, rule_id, state

7. **Reliability:**
   - VNF broker timeout: 30 seconds
   - Retry policy: 3 attempts with exponential backoff (1s, 2s, 4s)
   - Transaction safety: DB rollback on failure

8. **Observability:**
   - Structured logging: correlation ID, VNF instance ID, operation type
   - Metrics: operation count, success rate, latency distribution
   - Error messages surfaced to API responses (never swallow exceptions)

9. **Security:**
   - VNF broker auth: JWT token or API key (configurable)
   - Input validation: YAML size limits (< 1MB), rule parameter sanitization
   - Account isolation: users only see their own dictionaries/operations

### Acceptance Tests

**Test 1: Upload Dictionary**
```bash
cloudstack-cli vnf uploadDictionary template=vnf-pfsense yaml=@pfsense-2.7.yaml
# Expected: UUID returned, dictionary queryable, YAML stored
```

**Test 2: Create Firewall Rule (Idempotent)**
```bash
cloudstack-cli vnf createFirewallRule vnfInstanceId=123 ruleId=allow-http action=allow protocol=tcp destinationPort=80
cloudstack-cli vnf createFirewallRule vnfInstanceId=123 ruleId=allow-http action=allow protocol=tcp destinationPort=80
# Expected: Same operation UUID returned both times, single broker call
```

**Test 3: Test Connectivity**
```bash
cloudstack-cli vnf testConnectivity vnfApplianceId=456
# Expected: {reachable: true, latency: 45, lastContact: "2025-11-07T12:34:56Z"}
```

**Test 4: Reconcile Network**
```bash
cloudstack-cli vnf reconcileNetwork networkId=789
# Expected: {missing: [rule1, rule2], extra: [rule3], mismatched: []}
```

**Test 5: List Operations**
```bash
cloudstack-cli vnf listOperations vnfInstanceId=123 state=COMPLETED
# Expected: List of operations with full details
```

## Non-Goals (Explicitly Out of Scope)

- Real-time VNF metrics streaming
- VNF appliance auto-scaling
- Multi-region VNF management
- VNF marketplace/catalog
- Cost optimization recommendations
- Integration with third-party IPAM systems

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| VNF broker unavailable | Medium | High | Timeout + retry + error surfacing, document rollback |
| YAML schema variation | High | Medium | Extensible parser, vendor-specific handlers |
| Idempotency hash collisions | Low | High | SHA-256 hash of normalized params + UUID fallback |
| DB migration failure | Low | Critical | Test on dev/staging first, rollback script ready |
| VNF appliance API changes | Medium | Medium | Version dictionary schemas, deprecation notices |

## Timeline

- **T0 (Day 1-2):** Database schema + DAO layer + configuration
- **T+3 (Day 3-5):** VNF broker client + dictionary parser
- **T+6 (Day 6-10):** Service implementation (business logic)
- **T+11 (Day 11-13):** API commands + error handling + tests
- **T+14 (Day 14-15):** Observability + documentation + rollout

## Ownership

- **Implementation:** Build2 (Copilot) + Build1 (Codex) - independent parallel implementations
- **Code Review:** Cross-review between builds
- **Testing:** Both builds execute full test suite
- **Deployment:** Coordinated rollout, Build1 deploys first to staging

## Success Metrics (Post-Deploy)

- Zero P0/P1 incidents in first 30 days
- API success rate > 99.5%
- p95 latency < 2 seconds
- Operator feedback: "VNF management simpler than manual approach"

---
*Charter approved: 2025-11-07*
*Phase 1 target completion: 2025-11-22*
