# Guest-Side BGP Peering - CloudStack API Specification

**Feature:** VR Guest-Side BGP Peering  
**Target Release:** CloudStack 4.23 (Q2 2025)  
**API Version:** 4.23.0  
**Author:** Alexandre Mattioli (@alexandremattioli)  
**Date:** November 20, 2025

---

## Overview

This document specifies the CloudStack Management Server APIs for configuring and monitoring BGP peering between tenant VMs and Virtual Routers.

### API Categories

1. **Configuration APIs** - Enable/disable BGP, set parameters
2. **Monitoring APIs** - Query session state, routes, metrics
3. **Management APIs** - Troubleshooting, manual intervention

---

## Configuration APIs

### 1. updateNetworkOffering (Extended)

**Purpose:** Add guest BGP parameters to existing network offering API

**New Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `guestbgppeeringenabled` | boolean | No | false | Enable guest-side BGP peering |
| `guestbgpminprefixlength` | integer | No | 128 | Minimum allowed prefix length (64-128) |
| `guestbgpmaxprefixlength` | integer | No | 128 | Maximum allowed prefix length (64-128) |
| `guestbgpmaxprefixes` | integer | No | 10 | Max routes per VM (rate limiting) |
| `guestbgpallowedasnmin` | integer | No | 65200 | Minimum allowed tenant ASN |
| `guestbgpallowedasnmax` | integer | No | 65299 | Maximum allowed tenant ASN |

**Example Request:**

```bash
cloudmonkey update networkoffering \
  id=offering-uuid-123 \
  guestbgppeeringenabled=true \
  guestbgpminprefixlength=128 \
  guestbgpmaxprefixlength=128 \
  guestbgpmaxprefixes=10 \
  guestbgpallowedasnmin=65200 \
  guestbgpallowedasnmax=65299
```

**Response:**

```json
{
  "updatenetworkofferingresponse": {
    "networkoffering": {
      "id": "offering-uuid-123",
      "name": "Isolated with Guest BGP",
      "guestbgppeeringenabled": true,
      "guestbgpminprefixlength": 128,
      "guestbgpmaxprefixlength": 128,
      "guestbgpmaxprefixes": 10,
      "guestbgpallowedasnmin": 65200,
      "guestbgpallowedasnmax": 65299
    }
  }
}
```

---

### 2. listBgpGuestPeeringSessions (New)

**Purpose:** List all BGP peering sessions for guest VMs

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `networkid` | uuid | No | Filter by network ID |
| `virtualmachineid` | uuid | No | Filter by VM ID |
| `state` | string | No | Filter by session state (Idle, Connect, Active, Established) |
| `page` | integer | No | Page number (pagination) |
| `pagesize` | integer | No | Results per page (default: 20) |

**Example Request:**

```bash
cloudmonkey list bgp guest peering sessions \
  networkid=net-uuid-456 \
  state=Established
```

**Response:**

```json
{
  "listbgpguestpeeringsessionsresponse": {
    "count": 2,
    "bgppeeringsession": [
      {
        "id": "peer-uuid-abc",
        "networkid": "net-uuid-456",
        "networkname": "tenant-k8s-network",
        "virtualmachineid": "vm-uuid-789",
        "virtualmachinename": "k8s-node-1",
        "nicid": "nic-uuid-def",
        "guestip": "2a01:b000:1046:10:1::50",
        "guestasn": 65201,
        "vrip": "2a01:b000:1046:10:1::1",
        "vrasn": 65101,
        "state": "Established",
        "uptimeseconds": 3600,
        "prefixesreceived": 3,
        "prefixessent": 1,
        "lasterror": null,
        "created": "2025-11-20T10:00:00Z",
        "lastupdated": "2025-11-20T11:00:00Z"
      },
      {
        "id": "peer-uuid-xyz",
        "networkid": "net-uuid-456",
        "networkname": "tenant-k8s-network",
        "virtualmachineid": "vm-uuid-012",
        "virtualmachinename": "k8s-node-2",
        "nicid": "nic-uuid-ghi",
        "guestip": "2a01:b000:1046:10:1::51",
        "guestasn": 65202,
        "vrip": "2a01:b000:1046:10:1::1",
        "vrasn": 65101,
        "state": "Established",
        "uptimeseconds": 3500,
        "prefixesreceived": 2,
        "prefixessent": 1,
        "lasterror": null,
        "created": "2025-11-20T10:05:00Z",
        "lastupdated": "2025-11-20T11:00:00Z"
      }
    ]
  }
}
```

---

### 3. listBgpGuestRoutes (New)

**Purpose:** List BGP routes advertised by guest VMs

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `peeringid` | uuid | No | Filter by peering session ID |
| `networkid` | uuid | No | Filter by network ID |
| `state` | string | No | Filter by route state (Received, Accepted, Rejected, Withdrawn) |
| `page` | integer | No | Page number |
| `pagesize` | integer | No | Results per page (default: 50) |

**Example Request:**

```bash
cloudmonkey list bgp guest routes \
  peeringid=peer-uuid-abc \
  state=Accepted
```

**Response:**

```json
{
  "listbgpguestroutesresponse": {
    "count": 3,
    "bgpguestroute": [
      {
        "id": "route-uuid-001",
        "peeringid": "peer-uuid-abc",
        "prefix": "2a01:b000:1046:10:1::100/128",
        "prefixlength": 128,
        "nexthop": "2a01:b000:1046:10:1::50",
        "state": "Accepted",
        "rejectionreason": null,
        "receivedat": "2025-11-20T10:01:00Z",
        "acceptedat": "2025-11-20T10:01:01Z",
        "withdrawnat": null
      },
      {
        "id": "route-uuid-002",
        "peeringid": "peer-uuid-abc",
        "prefix": "2a01:b000:1046:10:1::101/128",
        "prefixlength": 128,
        "nexthop": "2a01:b000:1046:10:1::50",
        "state": "Accepted",
        "rejectionreason": null,
        "receivedat": "2025-11-20T10:02:00Z",
        "acceptedat": "2025-11-20T10:02:01Z",
        "withdrawnat": null
      },
      {
        "id": "route-uuid-003",
        "peeringid": "peer-uuid-abc",
        "prefix": "2a01:b000:1046:10:1::102/128",
        "prefixlength": 128,
        "nexthop": "2a01:b000:1046:10:1::50",
        "state": "Withdrawn",
        "rejectionreason": null,
        "receivedat": "2025-11-20T10:03:00Z",
        "acceptedat": "2025-11-20T10:03:01Z",
        "withdrawnat": "2025-11-20T10:30:00Z"
      }
    ]
  }
}
```

**Rejected Route Example:**

```bash
cloudmonkey list bgp guest routes \
  peeringid=peer-uuid-abc \
  state=Rejected
```

```json
{
  "listbgpguestroutesresponse": {
    "count": 1,
    "bgpguestroute": [
      {
        "id": "route-uuid-999",
        "peeringid": "peer-uuid-abc",
        "prefix": "2a01:b000:1046:20:1::100/128",
        "prefixlength": 128,
        "nexthop": "2a01:b000:1046:10:1::50",
        "state": "Rejected",
        "rejectionreason": "Prefix not in allowed range (2a01:b000:1046:10:1::/64)",
        "receivedat": "2025-11-20T10:15:00Z",
        "acceptedat": null,
        "withdrawnat": null
      }
    ]
  }
}
```

---

### 4. resetBgpGuestPeeringSession (New)

**Purpose:** Manually reset a BGP session (troubleshooting)

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | uuid | Yes | Peering session ID |

**Use Cases:**
- Session stuck in "Active" state
- Clear max-prefix violation
- Force route re-advertisement

**Example Request:**

```bash
cloudmonkey reset bgp guest peering session id=peer-uuid-abc
```

**Response:**

```json
{
  "resetbgpguestpeeringsessionresponse": {
    "success": true,
    "message": "BGP session reset initiated for peer-uuid-abc"
  }
}
```

**Implementation:**
- VR executes: `vtysh -c 'clear bgp ipv6 2a01:b000:1046:10:1::50'`
- Session tears down and re-establishes
- CloudStack updates state to "Idle" → "Connect" → "Established"

---

## Monitoring APIs

### 5. getBgpGuestPeeringMetrics (New)

**Purpose:** Retrieve detailed BGP metrics for a specific session

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | uuid | Yes | Peering session ID |

**Example Request:**

```bash
cloudmonkey get bgp guest peering metrics id=peer-uuid-abc
```

**Response:**

```json
{
  "getbgpguestpeeringmetricsresponse": {
    "peeringid": "peer-uuid-abc",
    "virtualmachineid": "vm-uuid-789",
    "state": "Established",
    "uptime": {
      "seconds": 3600,
      "formatted": "1h 0m 0s"
    },
    "prefixes": {
      "received": 3,
      "accepted": 3,
      "rejected": 1,
      "withdrawn": 0,
      "sent": 1
    },
    "messages": {
      "open": {
        "sent": 1,
        "received": 1
      },
      "update": {
        "sent": 4,
        "received": 5
      },
      "keepalive": {
        "sent": 60,
        "received": 60
      },
      "notification": {
        "sent": 0,
        "received": 0
      }
    },
    "lastread": "2025-11-20T11:00:58Z",
    "lastwrite": "2025-11-20T11:00:57Z",
    "tableversion": 5,
    "routertableentries": 3,
    "lasterror": null
  }
}
```

---

### 6. listBgpGuestPeeringEvents (New)

**Purpose:** Audit log of BGP session events

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `peeringid` | uuid | No | Filter by peering session |
| `networkid` | uuid | No | Filter by network |
| `eventtype` | string | No | Filter by event type |
| `startdate` | datetime | No | Filter events after date |
| `enddate` | datetime | No | Filter events before date |
| `page` | integer | No | Page number |
| `pagesize` | integer | No | Results per page (default: 50) |

**Event Types:**
- `SESSION_ESTABLISHED`
- `SESSION_DOWN`
- `ROUTE_ACCEPTED`
- `ROUTE_REJECTED`
- `ROUTE_WITHDRAWN`
- `MAX_PREFIX_VIOLATION`
- `INVALID_ASN`

**Example Request:**

```bash
cloudmonkey list bgp guest peering events \
  peeringid=peer-uuid-abc \
  eventtype=ROUTE_REJECTED
```

**Response:**

```json
{
  "listbgpguestpeeringeventsresponse": {
    "count": 2,
    "bgppeeringevent": [
      {
        "id": "event-uuid-001",
        "peeringid": "peer-uuid-abc",
        "eventtype": "ROUTE_REJECTED",
        "message": "Route 2a01:b000:1046:20:1::100/128 rejected: Prefix not in allowed range",
        "details": {
          "prefix": "2a01:b000:1046:20:1::100/128",
          "reason": "Prefix not in allowed range (2a01:b000:1046:10:1::/64)",
          "allowedrange": "2a01:b000:1046:10:1::/64"
        },
        "timestamp": "2025-11-20T10:15:00Z"
      },
      {
        "id": "event-uuid-002",
        "peeringid": "peer-uuid-abc",
        "eventtype": "ROUTE_REJECTED",
        "message": "Route 0::/0 rejected: Prefix length exceeds maximum",
        "details": {
          "prefix": "0::/0",
          "prefixlength": 0,
          "reason": "Prefix length 0 exceeds maximum allowed (128)",
          "maxallowed": 128
        },
        "timestamp": "2025-11-20T10:20:00Z"
      }
    ]
  }
}
```

---

## Administrative APIs

### 7. updateBgpGuestPeeringConfig (New)

**Purpose:** Update BGP parameters for a specific peering session

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | uuid | Yes | Peering session ID |
| `maxprefixes` | integer | No | Update max-prefix limit |

**Use Case:** Increase max-prefix limit for specific VM without changing network offering

**Example Request:**

```bash
cloudmonkey update bgp guest peering config \
  id=peer-uuid-abc \
  maxprefixes=20
```

**Response:**

```json
{
  "updatebgpguestpeeringconfigresponse": {
    "success": true,
    "peeringid": "peer-uuid-abc",
    "maxprefixes": 20,
    "message": "BGP session configuration updated. Session will be reset."
  }
}
```

**Implementation:**
- Update VR FRR config: `neighbor <ip> maximum-prefix 20`
- Reset BGP session to apply changes

---

### 8. deleteBgpGuestPeeringSession (New)

**Purpose:** Force-delete a BGP peering session (cleanup)

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | uuid | Yes | Peering session ID |

**Use Case:** Remove stale session after VM deletion

**Example Request:**

```bash
cloudmonkey delete bgp guest peering session id=peer-uuid-abc
```

**Response:**

```json
{
  "deletebgpguestpeeringsessionresponse": {
    "success": true,
    "message": "BGP peering session peer-uuid-abc deleted"
  }
}
```

**Implementation:**
- Mark session as removed in database
- VR automatically drops session when VM stops advertising
- CloudStack cleans up database records

---

## Error Responses

### Standard Error Format

```json
{
  "errorresponse": {
    "uuidList": [],
    "errorcode": 431,
    "errortext": "BGP peering not enabled for network offering"
  }
}
```

### Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 431 | `BGP_PEERING_NOT_ENABLED` | Network offering doesn't support guest BGP |
| 432 | `INVALID_ASN_RANGE` | ASN outside allowed range |
| 433 | `MAX_PREFIX_EXCEEDED` | Too many prefixes advertised |
| 434 | `SESSION_NOT_FOUND` | Peering session ID doesn't exist |
| 435 | `NETWORK_NOT_FOUND` | Network ID doesn't exist |
| 436 | `VM_NOT_FOUND` | Virtual machine ID doesn't exist |
| 437 | `INVALID_PREFIX_LENGTH` | Prefix length outside min/max bounds |

---

## API Usage Examples

### Example 1: Enable Guest BGP for New Network

```bash
# Step 1: Create network offering with guest BGP
cloudmonkey create networkoffering \
  name="Isolated with Guest BGP" \
  displaytext="Isolated network with guest-side BGP peering" \
  guestiptype=Isolated \
  supportedservices=Dhcp,Dns,Firewall,Lb,SourceNat,StaticNat,Vpn,DynamicRouting \
  serviceProviderList[0].service=DynamicRouting \
  serviceProviderList[0].provider=VirtualRouter \
  guestbgppeeringenabled=true \
  guestbgpmaxprefixes=10

# Step 2: Enable offering
cloudmonkey update networkoffering id=<offering-id> state=Enabled

# Step 3: Create network using offering
cloudmonkey create network \
  name="k8s-cluster-network" \
  displaytext="Kubernetes cluster with BGP" \
  networkofferingid=<offering-id> \
  zoneid=<zone-id>

# Step 4: Deploy VM in network
cloudmonkey deploy virtualmachine \
  serviceofferingid=<service-offering-id> \
  templateid=<template-id> \
  zoneid=<zone-id> \
  networkids=<network-id>

# Step 5: VM starts BGP daemon (manual step on VM)
# ssh into VM, configure FRR to peer with VR

# Step 6: Monitor session
cloudmonkey list bgp guest peering sessions networkid=<network-id>
```

---

### Example 2: Troubleshoot Route Rejection

```bash
# Step 1: Check session state
cloudmonkey list bgp guest peering sessions virtualmachineid=<vm-id>

# Step 2: List all routes (including rejected)
cloudmonkey list bgp guest routes peeringid=<peer-id>

# Step 3: Filter rejected routes
cloudmonkey list bgp guest routes peeringid=<peer-id> state=Rejected

# Sample output:
# {
#   "prefix": "2a01:b000:1046:20:1::100/128",
#   "state": "Rejected",
#   "rejectionreason": "Prefix not in allowed range (2a01:b000:1046:10:1::/64)"
# }

# Step 4: Check network offering constraints
cloudmonkey list networkofferings id=<offering-id>

# Step 5: Fix VM's BGP config to advertise valid prefixes
# (Manual step: reconfigure FRR on VM)
```

---

### Example 3: Monitor Session Metrics

```bash
# Get detailed metrics
cloudmonkey get bgp guest peering metrics id=<peer-id>

# List recent events
cloudmonkey list bgp guest peering events \
  peeringid=<peer-id> \
  startdate="2025-11-20T00:00:00Z"

# Check for max-prefix violations
cloudmonkey list bgp guest peering events \
  eventtype=MAX_PREFIX_VIOLATION
```

---

## API Permissions

### Role-Based Access Control

| API | Root Admin | Domain Admin | User | Read-Only Admin |
|-----|-----------|--------------|------|-----------------|
| `updateNetworkOffering` (guest BGP params) | ✅ | ❌ | ❌ | ❌ |
| `listBgpGuestPeeringSessions` | ✅ | ✅ (own domain) | ✅ (own VMs) | ✅ |
| `listBgpGuestRoutes` | ✅ | ✅ (own domain) | ✅ (own VMs) | ✅ |
| `getBgpGuestPeeringMetrics` | ✅ | ✅ (own domain) | ✅ (own VMs) | ✅ |
| `listBgpGuestPeeringEvents` | ✅ | ✅ (own domain) | ✅ (own VMs) | ✅ |
| `resetBgpGuestPeeringSession` | ✅ | ✅ (own domain) | ❌ | ❌ |
| `updateBgpGuestPeeringConfig` | ✅ | ✅ (own domain) | ❌ | ❌ |
| `deleteBgpGuestPeeringSession` | ✅ | ❌ | ❌ | ❌ |

---

## API Implementation Notes

### Database Queries

**listBgpGuestPeeringSessions:**
```sql
SELECT 
  bgp.*, 
  vm.name AS vm_name, 
  net.name AS network_name
FROM bgp_guest_peering bgp
JOIN vm_instance vm ON bgp.vm_id = vm.id
JOIN networks net ON bgp.network_id = net.id
WHERE 
  bgp.removed IS NULL
  AND (bgp.network_id = ? OR ? IS NULL)
  AND (bgp.vm_id = ? OR ? IS NULL)
  AND (bgp.state = ? OR ? IS NULL)
ORDER BY bgp.created DESC
LIMIT ? OFFSET ?;
```

**listBgpGuestRoutes:**
```sql
SELECT * FROM bgp_guest_routes
WHERE 
  (peering_id = ? OR ? IS NULL)
  AND (state = ? OR ? IS NULL)
ORDER BY received_at DESC
LIMIT ? OFFSET ?;
```

### VR Integration

**Polling Mechanism:**
- CloudStack Management Server polls VR every 60 seconds
- VR agent executes: `vtysh -c 'show bgp ipv6 unicast summary json'`
- Parses JSON output, updates `bgp_guest_peering` table
- Detects new sessions (not in DB) → auto-create record

**FRR JSON Output Example:**
```json
{
  "ipv6Unicast": {
    "peers": {
      "2a01:b000:1046:10:1::50": {
        "remoteAs": 65201,
        "state": "Established",
        "peerUptime": "01:00:00",
        "prefixReceivedCount": 3,
        "prefixSentCount": 1
      }
    }
  }
}
```

---

## Backward Compatibility

### Existing API Behavior

**No Breaking Changes:**
- All new APIs are additive
- Existing `updateNetworkOffering` API extended with optional parameters
- Networks without guest BGP continue to work unchanged

**Migration Path:**
- CloudStack 4.22 → 4.23 upgrade: Guest BGP disabled by default
- Admins must explicitly enable via network offering update
- No automatic migration of existing networks

---

## Future API Enhancements (Phase 2)

### Planned APIs (CloudStack 4.24+)

1. **configureBgpGuestAuthentication** - Set MD5 password per session
2. **listBgpGuestCommunities** - Query BGP communities (Phase 3 feature)
3. **createBgpGuestRouteFilter** - Custom prefix filters per VM
4. **getBgpGuestPeeringStatistics** - Prometheus-compatible metrics export

---

## References

- **Feature Overview:** `/Builder2/Build/Features/guestBGP/README.md`
- **Technical Design:** `/Builder2/Build/Features/guestBGP/DESIGN_SPECIFICATION.md`
- **CloudStack API Docs:** https://cloudstack.apache.org/api.html
- **FRR BGP Commands:** https://docs.frrouting.org/en/latest/bgp.html

---

**Status:** API Design Complete - Ready for Implementation  
**Next Steps:** Implement API handlers in CloudStack Management Server  
**Last Updated:** November 20, 2025
