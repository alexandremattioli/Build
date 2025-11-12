# VNF Framework UI Design Specification
## CloudStack Primate UI Integration

**Version:** 1.0  
**Target:** Apache CloudStack 4.21.7 Primate UI  
**Framework:** Vue.js 3 + Ant Design Vue  
**Date:** November 4, 2025

---

## Table of Contents
1. [Overview](#overview)
2. [User Flows](#user-flows)
3. [Screen Specifications](#screen-specifications)
4. [Component Requirements](#component-requirements)
5. [API Integration](#api-integration)
6. [Mock UI Requirements](#mock-ui-requirements)

---

## Overview

### Design Philosophy
The VNF Framework UI follows CloudStack Primate's existing patterns:
- **Minimal disruption** - Extends existing screens rather than creating new sections
- **Progressive disclosure** - Shows VNF options only when relevant
- **Familiar patterns** - Uses existing CloudStack UI components and conventions
- **Self-service capable** - Domain admins can manage VNF templates and networks

### Key UI Areas
1. **Templates Screen** - Upload/manage VNF dictionaries
2. **Network Creation** - Select VNF template for network appliance
3. **Network Details** - View VNF health, trigger reconciliation, test connectivity
4. **Guest Network Rules** - No UI changes (uses existing firewall/NAT screens)

---

## User Flows

### Flow 1: Register VNF Template with Dictionary
**Actor:** Root Admin or Domain Admin  
**Goal:** Make a VNF appliance (pfSense, FortiGate) available for use

```
1. Navigate to Templates → Filter by "VNF" or "Router"
2. Click existing VNF template (or register new one)
3. In template details, see new "VNF Configuration" tab
4. Upload YAML dictionary file OR paste YAML content
5. System validates dictionary (shows errors/warnings inline)
6. Click "Save Dictionary"
7. Template now marked as "VNF-Ready" (green badge)
```

**Success:** Template shows green "VNF Ready" badge, dictionary version displayed

### Flow 2: Create VNF-Backed Network
**Actor:** Domain Admin or User (with network creation permission)  
**Goal:** Deploy a guest network using VNF appliance instead of Virtual Router

```
1. Navigate to Networks → Add Network
2. Select Network Offering (must support Source NAT + VNF)
3. New section appears: "Network Appliance"
   - Radio buttons: [ ] Virtual Router (default)  [X] VNF Appliance
4. When VNF selected, dropdown appears: "Select VNF Template"
   - Shows only VNF-ready templates (with green badge)
5. Optional: "Dictionary Overrides" accordion
   - Can override specific YAML values (expert mode)
6. Click "Create Network"
7. Network deploys VNF VM + DHCP/DNS VR (if needed)
```

**Success:** Network details show VNF appliance VM, health status, connectivity indicator

### Flow 3: Monitor VNF Network Health
**Actor:** Network Owner or Admin  
**Goal:** Check if VNF appliance is healthy and in sync

```
1. Navigate to Networks → Select VNF-backed network
2. Network details page shows new "VNF Status" card:
   - Health indicator: Green (healthy) / Yellow (degraded) / Red (unreachable)
   - Last reconciliation: "2 hours ago"
   - Drift status: "In sync" or "3 rules out of sync"
   - Connectivity: "Reachable via broker" or error message
3. Click "Test Connectivity" button → runs test → shows latency
4. Click "Reconcile Now" button → triggers reconciliation → shows progress
5. View reconciliation history in "VNF Audit Log" section
```

**Success:** Can see health at a glance, trigger reconciliation on-demand

### Flow 4: Manage Firewall Rules (No Change)
**Actor:** Network Owner  
**Goal:** Add/remove firewall rules (works same as before)

```
1. Navigate to Networks → Select network → Firewall tab
2. Add/remove rules using existing UI (no changes)
3. Rules applied to VNF appliance instead of VR
4. External rule IDs stored automatically (invisible to user)
```

**Success:** User doesn't need to know VNF vs VR - same experience

### Flow 5: Troubleshoot VNF Issues
**Actor:** Admin  
**Goal:** Debug why VNF network isn't working

```
1. Navigate to Networks → Select VNF network
2. VNF Status card shows error: "Unreachable - Broker timeout"
3. Click "View Details" → Expands to show:
   - Broker logs (last 20 entries)
   - Last successful request timestamp
   - VNF appliance IP and credentials status
   - Dictionary validation status
4. Click "Test Components" → Runs diagnostics:
   - [OK] VNF VM is running
   - [OK] Broker service is up
   - ✗ VNF API not responding on port 443
   - Recommendation: "Check VNF firewall rules"
5. Click "View Audit Log" → Shows all requests/responses
```

**Success:** Can identify issue quickly (broker vs VNF vs dictionary problem)

---

## Screen Specifications

### 1. Templates Screen - VNF Configuration Tab

**Location:** Compute → Templates → [Template Details] → VNF Configuration (new tab)

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ VNF Configuration                                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ [VNF Ready Badge: Green [OK]] Dictionary Version: 2.1.0       │
│                             Last Updated: Nov 4, 2025       │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Upload Dictionary                                       ││
│ │                                                         ││
│ │ [ ] Upload YAML File                                    ││
│ │     [Choose File] No file selected                      ││
│ │                                                         ││
│ │ [X] Paste YAML Content                                  ││
│ │     ┌─────────────────────────────────────────────────┐ ││
│ │     │ metadata:                                       │ ││
│ │     │   vendor: "pfSense"                             │ ││
│ │     │   version: "2.7.0"                              │ ││
│ │     │   api_type: "REST"                              │ ││
│ │     │ ...                                             │ ││
│ │     └─────────────────────────────────────────────────┘ ││
│ │                                                         ││
│ │ [Validate]  [Save Dictionary]                           ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ Validation Results:                                         │
│ [OK] Metadata section valid                                    │
│ [OK] Services section valid (3 services defined)               │
│ ⚠ Warning: No 'loadbalancer' service defined                │
│ [OK] All placeholders use valid CloudStack context             │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Current Dictionary Info                                 ││
│ │                                                         ││
│ │ Vendor:        pfSense                                  ││
│ │ Version:       2.7.0                                    ││
│ │ API Type:      REST                                     ││
│ │ Auth:          API Token                                ││
│ │ Base URL:      https://{vnf.management.ip}/api/v2       ││
│ │                                                         ││
│ │ Supported Services:                                     ││
│ │ • Firewall (create, delete, list)                       ││
│ │ • NAT (create_portforward, delete_portforward, list)    ││
│ │ • Static Routes (create, delete, list)                  ││
│ │                                                         ││
│ │ [View Full Dictionary]  [Download YAML]                 ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ Dictionary Version History:                                 │
│ ┌──────┬────────────┬──────────────┬───────────────────────┐│
│ │ Ver  │ Date       │ Updated By   │ Actions               ││
│ ├──────┼────────────┼──────────────┼───────────────────────┤│
│ │ 2.1.0│ Nov 4 2025 │ admin        │ [View] [Rollback]     ││
│ │ 2.0.0│ Oct 1 2025 │ admin        │ [View] [Rollback]     ││
│ │ 1.0.0│ Sep 1 2025 │ admin        │ [View]                ││
│ └──────┴────────────┴──────────────┴───────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- `VnfDictionaryUploader` - File upload or paste textarea
- `VnfDictionaryValidator` - Real-time validation with inline feedback
- `VnfDictionaryInfo` - Read-only display of current dictionary
- `VnfDictionaryHistory` - Version history table with rollback

**API Calls:**
- `updateTemplateDictionary` - Save new dictionary
- `getTemplateDictionary` - Load current dictionary
- `listDictionaryVersions` - Get version history
- `validateDictionary` - Validate YAML before save

---

### 2. Create Network Screen - VNF Appliance Selection

**Location:** Network → Add Network (wizard step 3)

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Create Network - Step 3: Network Configuration             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Network Appliance Type:                                     │
│                                                             │
│ (•) Virtual Router                                          │
│     Traditional CloudStack Virtual Router for all services  │
│     Includes: DHCP, DNS, Source NAT, Firewall, Port Fwd     │
│                                                             │
│ ( ) VNF Appliance                                           │
│     Use third-party network appliance (pfSense, FortiGate)  │
│     Requires: VNF template, DHCP/DNS VR for guest services  │
│     Supports: Source NAT, Firewall, Port Fwd, Load Balancer │
│                                                             │
│ [When VNF selected, show additional section:]               │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ VNF Template Selection                                  ││
│ │                                                         ││
│ │ Select VNF Template: *                                  ││
│ │ ┌─────────────────────────────────────────────────────┐ ││
│ │ │ [√] pfSense 2.7.0 Community Edition                │ ││
│ │ │     Vendor: pfSense | API: REST                     │ ││
│ │ │     Services: Firewall, NAT, Routing                │ ││
│ │ │     [VNF Ready [OK]]                                   │ ││
│ │ └─────────────────────────────────────────────────────┘ ││
│ │ [ ] FortiGate 7.4.0                                     ││
│ │     Vendor: Fortinet | API: REST                        ││
│ │     Services: Firewall, NAT, Load Balancer              ││
│ │     [VNF Ready [OK]]                                       ││
│ │                                                         ││
│ │ [ ] Palo Alto PAN-OS 11.0                               ││
│ │     Vendor: Palo Alto Networks | API: XML               ││
│ │     Services: Firewall, NAT, SSL VPN                    ││
│ │     [VNF Ready [OK]]                                       ││
│ │                                                         ││
│ │ Advanced Options: [Expand ▼]                            ││
│ │ ┌─────────────────────────────────────────────────────┐ ││
│ │ │ Dictionary Overrides (Optional)                     │ ││
│ │ │ Override specific dictionary values for this network│ ││
│ │ │                                                     │ ││
│ │ │ Key: [api_port          ▼] Value: [8443]           │ ││
│ │ │ [+ Add Override]                                    │ ││
│ │ └─────────────────────────────────────────────────────┘ ││
│ │                                                         ││
│ │ VNF Credentials:                                        ││
│ │ Username: [admin                        ]               ││
│ │ Password: [********************         ]               ││
│ │ (Stored encrypted, used for API authentication)         ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ Network Configuration:                                      │
│ Gateway:      [10.1.1.1    ]                               │
│ Netmask:      [255.255.255.0]                              │
│ VLAN ID:      [100         ]                               │
│                                                             │
│                                   [Cancel]  [Previous]  [Create Network]
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- `NetworkApplianceSelector` - Radio buttons with descriptions
- `VnfTemplateSelector` - Template cards with metadata
- `VnfDictionaryOverrides` - Key-value pair editor
- `VnfCredentialsInput` - Secure credential fields

**API Calls:**
- `listTemplates` (filter: `vnf_ready=true`)
- `getTemplateDictionary` - Load dictionary for preview
- `createNetwork` - Create network with VNF parameters

---

### 3. Network Details Screen - VNF Status Card

**Location:** Network → [Network Details] → Overview (new card)

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ VNF Appliance Status                           [Refresh ↻] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ● Health: Healthy                    Last Check: 2 min ago │
│                                                             │
│ ┌──────────────┬──────────────┬──────────────┬────────────┐│
│ │ Connectivity │ Rules in Sync│ Last Reconcile│ API Latency││
│ │   [OK] Online   │   12 / 12    │  2 hours ago │   45ms     ││
│ └──────────────┴──────────────┴──────────────┴────────────┘│
│                                                             │
│ VNF Appliance Details:                                      │
│ • Name:         pfSense-Network-123                         │
│ • Template:     pfSense 2.7.0 Community Edition             │
│ • Management IP: 192.168.1.10                               │
│ • Dictionary:   pfSense v2.1.0                              │
│ • Broker:       VR-123-456 (192.168.100.5:8445)             │
│                                                             │
│ [Test Connectivity]  [Reconcile Now]  [View Audit Log]      │
│                                                             │
│ Drift Detection:                                            │
│ [OK] All firewall rules in sync                                │
│ [OK] All port forwarding rules in sync                         │
│ [OK] All static routes in sync                                 │
│                                                             │
│ [When drift detected:]                                      │
│ ⚠ 3 rules out of sync - Last reconciliation failed          │
│ • Firewall rule "Allow-SSH" missing on device               │
│ • Port forward 80→8080 has wrong target IP                  │
│ • Static route 10.0.0.0/8 not found on device               │
│                                                             │
│ [Auto-Fix Rules]  [View Details]                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘

[Expand "VNF Audit Log" section:]

┌─────────────────────────────────────────────────────────────┐
│ VNF Audit Log                          [Export] [Filter ▼] │
├─────────────────────────────────────────────────────────────┤
│ ┌──────────────┬──────────┬─────────┬──────────────────────┐│
│ │ Timestamp    │ Operation│ Status  │ Details              ││
│ ├──────────────┼──────────┼─────────┼──────────────────────┤│
│ │ Nov 4 14:32  │ Reconcile│ Success │ 12 rules checked     ││
│ │ Nov 4 14:15  │ AddFwRule│ Success │ Rule: Allow-HTTPS    ││
│ │ Nov 4 14:10  │ DelFwRule│ Success │ Rule: Deny-Telnet    ││
│ │ Nov 4 12:05  │ TestConn │ Success │ Latency: 45ms        ││
│ │ Nov 4 10:00  │ Reconcile│ Warning │ 1 rule out of sync   ││
│ └──────────────┴──────────┴─────────┴──────────────────────┘│
│                                                             │
│ [Click any row to expand details]                           │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Operation: Add Firewall Rule                            ││
│ │ Timestamp: Nov 4, 2025 14:15:23                         ││
│ │ Status:    Success                                      ││
│ │                                                         ││
│ │ Request:                                                ││
│ │ POST /api/v2/firewall/rules                             ││
│ │ {                                                       ││
│ │   "action": "pass",                                     ││
│ │   "protocol": "tcp",                                    ││
│ │   "source": "any",                                      ││
│ │   "destination": "10.1.1.100",                          ││
│ │   "port": "443"                                         ││
│ │ }                                                       ││
│ │                                                         ││
│ │ Response:                                               ││
│ │ HTTP 200 OK                                             ││
│ │ {                                                       ││
│ │   "id": "5e3a4b2c1d",                                   ││
│ │   "status": "created"                                   ││
│ │ }                                                       ││
│ │                                                         ││
│ │ External Rule ID: 5e3a4b2c1d                            ││
│ │ Execution Time: 127ms                                   ││
│ └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- `VnfHealthCard` - Status indicators and metrics
- `VnfDriftIndicator` - Sync status with details
- `VnfAuditLog` - Sortable/filterable audit table
- `VnfOperationDetails` - Request/response viewer

**API Calls:**
- `getVnfStatus` - Get health and connectivity
- `testVnfConnectivity` - Run connectivity test
- `reconcileVnfNetwork` - Trigger reconciliation
- `listVnfAuditLog` - Get audit history

---

### 4. Connectivity Test Modal

**Trigger:** Click "Test Connectivity" button  
**Purpose:** Verify VNF appliance is reachable and responding

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Test VNF Connectivity                             [Close ✕]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Testing connectivity to pfSense-Network-123...              │
│                                                             │
│ [Progress Bar: ████████████████░░░░░░░░] 75%               │
│                                                             │
│ [OK] VNF VM is running (192.168.1.10)                          │
│ [OK] Broker service is reachable (VR-123-456:8445)             │
│ [OK] JWT token valid                                           │
│ [OK] VNF API responding on HTTPS (port 443)                    │
│ ⏳ Testing authentication...                                │
│                                                             │
│ [After completion:]                                         │
│                                                             │
│ [OK] All Tests Passed                                         │
│                                                             │
│ [OK] VNF VM is running                                         │
│ [OK] Broker service is reachable                               │
│ [OK] JWT token valid                                           │
│ [OK] VNF API responding                                        │
│ [OK] Authentication successful                                 │
│ [OK] Test rule created and deleted                             │
│                                                             │
│ Connectivity Metrics:                                       │
│ • Round-trip latency:  45ms                                 │
│ • Broker latency:      12ms                                 │
│ • API latency:         33ms                                 │
│                                                             │
│                                   [Close]  [Run Again]      │
└─────────────────────────────────────────────────────────────┘

[If errors occur:]

┌─────────────────────────────────────────────────────────────┐
│ Test VNF Connectivity                             [Close ✕]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ [X] Connectivity Test Failed                                 │
│                                                             │
│ [OK] VNF VM is running                                         │
│ [OK] Broker service is reachable                               │
│ [OK] JWT token valid                                           │
│ ✗ VNF API not responding on HTTPS (port 443)                │
│   Error: Connection timeout after 10 seconds                │
│   Troubleshooting:                                          │
│   • Check VNF firewall allows access from broker IP         │
│   • Verify API service is running on VNF                    │
│   • Confirm management network connectivity                 │
│                                                             │
│                         [Close]  [View Logs]  [Run Again]   │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- `VnfConnectivityTest` - Step-by-step test progress
- `VnfTestResults` - Results display with metrics
- `VnfTroubleshooting` - Error-specific recommendations

**API Calls:**
- `testVnfConnectivity` - Run full connectivity test

---

### 5. Reconciliation Modal

**Trigger:** Click "Reconcile Now" button  
**Purpose:** Sync CloudStack rules with VNF device state

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ VNF Reconciliation                                [Close ✕]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Reconciling network: Guest-Network-123                      │
│                                                             │
│ [Progress Bar: ████████████████████████░░] 90%             │
│                                                             │
│ Phase 1: Query CloudStack State                             │
│ [OK] Found 12 firewall rules in database                       │
│ [OK] Found 5 port forwarding rules in database                 │
│ [OK] Found 2 static routes in database                         │
│                                                             │
│ Phase 2: Query VNF Device State                             │
│ [OK] Retrieved 11 firewall rules from device                   │
│ [OK] Retrieved 5 port forwarding rules from device             │
│ [OK] Retrieved 2 static routes from device                     │
│                                                             │
│ Phase 3: Compare and Identify Drift                         │
│ ⚠ Found 3 discrepancies                                     │
│                                                             │
│ Phase 4: Apply Fixes                                        │
│ ⏳ Creating missing firewall rule "Allow-SSH"...            │
│                                                             │
│ [After completion:]                                         │
│                                                             │
│ [OK] Reconciliation Complete                                  │
│                                                             │
│ Summary:                                                    │
│ • Total rules checked:    19                                │
│ • Rules in sync:          16                                │
│ • Rules created on device: 2                                │
│ • Rules deleted from device: 1                              │
│ • Errors:                  0                                │
│                                                             │
│ Detailed Changes:                                           │
│ ┌──────────────┬────────────────────────┬─────────────────┐│
│ │ Action       │ Rule                   │ Status          ││
│ ├──────────────┼────────────────────────┼─────────────────┤│
│ │ Created      │ Firewall: Allow-SSH    │ [OK] Success       ││
│ │ Created      │ Firewall: Allow-HTTPS  │ [OK] Success       ││
│ │ Deleted      │ PortFwd: 80→8080 (old) │ [OK] Success       ││
│ └──────────────┴────────────────────────┴─────────────────┘│
│                                                             │
│ Next automatic reconciliation: in 6 hours                   │
│                                                             │
│                         [Close]  [View Full Report]         │
└─────────────────────────────────────────────────────────────┘
```

**Components:**
- `VnfReconciliationProgress` - Multi-phase progress indicator
- `VnfReconciliationResults` - Summary and detailed changes
- `VnfReconciliationReport` - Downloadable full report

**API Calls:**
- `reconcileVnfNetwork` - Trigger reconciliation
- `getReconciliationStatus` - Poll for progress (async operation)

---

## Component Requirements

### Vue.js Components to Build

#### 1. **VnfDictionaryUploader.vue**
```javascript
// Props:
{
  templateId: String,
  existingDictionary: Object
}

// Events:
- @dictionary-uploaded
- @validation-complete
- @save-complete

// Data:
{
  uploadMode: 'file' | 'paste',
  yamlContent: String,
  validationResults: Array,
  isValidating: Boolean,
  isSaving: Boolean
}

// Methods:
- validateDictionary()
- saveDictionary()
- loadDictionary()
```

#### 2. **VnfTemplateSelector.vue**
```javascript
// Props:
{
  networkOfferingId: String,
  selectedTemplateId: String
}

// Events:
- @template-selected
- @template-changed

// Data:
{
  vnfTemplates: Array,
  selectedTemplate: Object,
  showAdvanced: Boolean,
  overrides: Array
}

// Methods:
- loadVnfTemplates()
- selectTemplate(templateId)
- addOverride(key, value)
```

#### 3. **VnfHealthCard.vue**
```javascript
// Props:
{
  networkId: String,
  refreshInterval: Number  // default 60000 (1 min)
}

// Events:
- @test-connectivity
- @reconcile-now
- @view-audit-log

// Data:
{
  healthStatus: 'healthy' | 'degraded' | 'unreachable',
  connectivity: Boolean,
  driftCount: Number,
  lastReconcile: Date,
  apiLatency: Number,
  vnfDetails: Object
}

// Methods:
- fetchStatus()
- testConnectivity()
- reconcile()
- autoRefresh()
```

#### 4. **VnfConnectivityTest.vue**
```javascript
// Props:
{
  networkId: String,
  vnfApplianceId: String
}

// Events:
- @test-complete
- @test-failed

// Data:
{
  testSteps: Array,
  currentStep: Number,
  testResults: Object,
  isRunning: Boolean,
  metrics: Object
}

// Methods:
- runTest()
- checkStep(stepName)
- generateRecommendations()
```

#### 5. **VnfAuditLog.vue**
```javascript
// Props:
{
  networkId: String,
  limit: Number,  // default 50
  autoRefresh: Boolean
}

// Events:
- @row-clicked
- @export-requested

// Data:
{
  auditEntries: Array,
  filters: Object,
  selectedEntry: Object,
  pagination: Object
}

// Methods:
- fetchAuditLog()
- filterByOperation(operation)
- exportToCSV()
- expandDetails(entry)
```

#### 6. **VnfReconciliation.vue**
```javascript
// Props:
{
  networkId: String
}

// Events:
- @reconciliation-complete
- @reconciliation-failed

// Data:
{
  isRunning: Boolean,
  currentPhase: String,
  progress: Number,
  results: Object,
  changes: Array
}

// Methods:
- startReconciliation()
- pollStatus()
- showResults()
- downloadReport()
```

---

## API Integration

### Required API Endpoints (from vnf-api-spec.yaml)

1. **updateTemplateDictionary**
   - POST `/api/v1/updateTemplateDictionary`
   - Upload/update YAML dictionary for VNF template

2. **listTemplates** (existing, extended)
   - GET `/api/v1/listTemplates?vnf_ready=true`
   - Returns templates with VNF dictionary attached

3. **createNetwork** (existing, extended)
   - POST `/api/v1/createNetwork`
   - Additional params: `vnftemplateid`, `vnfcredentials`, `vnfoverrides`

4. **listVnfAppliances**
   - GET `/api/v1/listVnfAppliances`
   - Returns VNF appliance VMs with health status

5. **testVnfConnectivity**
   - POST `/api/v1/testVnfConnectivity`
   - Params: `networkid`
   - Returns connectivity test results

6. **reconcileVnfNetwork**
   - POST `/api/v1/reconcileVnfNetwork`
   - Params: `networkid`, `autofix=true`
   - Returns reconciliation job ID (async)

7. **getReconciliationStatus**
   - GET `/api/v1/getReconciliationStatus?jobid=xxx`
   - Poll for reconciliation progress

8. **listVnfAuditLog**
   - GET `/api/v1/listVnfAuditLog?networkid=xxx`
   - Returns audit history with pagination

---

## Mock UI Requirements

### For Codex/Copilot to Generate Mock UI

**You need to provide:**

1. **This UI specification document** [OK] (this file)
2. **Component specifications** (detailed props/events/methods)
3. **Mock data files** (JSON responses for all APIs)
4. **Primate UI context** (existing patterns and component examples)

**What Copilot should generate:**

1. **Vue.js components** (.vue files):
   - `VnfDictionaryUploader.vue`
   - `VnfTemplateSelector.vue`
   - `VnfHealthCard.vue`
   - `VnfConnectivityTest.vue`
   - `VnfAuditLog.vue`
   - `VnfReconciliation.vue`

2. **API mock service** (api/vnf.js):
   - Mock implementations returning realistic data
   - Simulated delays (200-500ms)
   - Error scenarios (10% failure rate)

3. **Mock data generators** (mockData/vnf.js):
   - Template data with dictionaries
   - Health status variations
   - Audit log entries
   - Reconciliation results

4. **Router integration** (router/index.js):
   - Routes for new VNF screens
   - Navigation guards

5. **Store modules** (store/modules/vnf.js):
   - Vuex store for VNF state
   - Actions for API calls
   - Getters for computed data

6. **CSS/Styling** (styles/vnf.scss):
   - Health indicators (colors)
   - Status badges
   - Card layouts
   - Responsive design

### Copilot Prompt Example

```
Generate a complete Vue.js mock UI for the VNF Framework feature in CloudStack Primate UI.

Context:
- Vue 3 + Ant Design Vue
- Follow CloudStack Primate conventions
- Use existing components where possible (a-card, a-table, a-button, etc.)

Requirements:
1. Read ui-specs/UI-DESIGN-SPECIFICATION.md for all screen layouts
2. Read ui-specs/COMPONENT-SPECIFICATIONS.md for component details
3. Use mock-data/*.json files for API responses
4. Follow existing Primate patterns in views/network/* for style

Generate:
- 6 Vue components in src/views/infra/vnf/
- API mock service in src/api/vnf.js
- Store module in src/store/modules/vnf.js
- Add routes to src/router/index.js

Make it functional with realistic interactions (not just static UI).
```

---

## Testing Requirements

### Manual Testing Checklist

**Templates Screen:**
- [ ] Upload YAML file shows validation results
- [ ] Paste YAML content validates in real-time
- [ ] Invalid YAML shows clear error messages
- [ ] Save dictionary updates VNF Ready badge
- [ ] Version history shows previous dictionaries
- [ ] Rollback restores previous version

**Network Creation:**
- [ ] VNF option only available for compatible offerings
- [ ] Template selector shows only VNF-ready templates
- [ ] Dictionary overrides are optional
- [ ] Credentials are masked (password field)
- [ ] Network creates successfully with VNF

**Network Details:**
- [ ] Health card shows correct status colors
- [ ] Test connectivity runs and shows progress
- [ ] Reconcile now triggers and shows results
- [ ] Audit log loads and filters correctly
- [ ] Drift indicator updates after reconciliation

**Error Scenarios:**
- [ ] Network unreachable shows red status
- [ ] API timeout shows error message
- [ ] Invalid credentials shows auth error
- [ ] Dictionary validation fails gracefully
- [ ] Reconciliation errors are logged

### Automated Testing

**Unit Tests (Jest + Vue Test Utils):**
```javascript
// VnfHealthCard.spec.js
describe('VnfHealthCard', () => {
  it('renders healthy status correctly', () => {})
  it('shows degraded status with warnings', () => {})
  it('displays unreachable status with error', () => {})
  it('fetches status on mount', () => {})
  it('auto-refreshes every 60 seconds', () => {})
  it('emits test-connectivity event on button click', () => {})
})
```

**Integration Tests:**
- Mock API responses with MSW (Mock Service Worker)
- Test full user flows (template upload → network creation → reconciliation)
- Test error handling and retry logic

---

## Accessibility Requirements

- **WCAG 2.1 Level AA** compliance
- **Keyboard navigation** for all actions
- **ARIA labels** for status indicators
- **Color contrast** meets minimum 4.5:1 ratio
- **Screen reader** support for all components
- **Focus indicators** visible on all interactive elements

---

## Performance Requirements

- **Initial load** < 2 seconds
- **API calls** should not block UI
- **Optimistic updates** for better UX (show success, revert on error)
- **Pagination** for large audit logs (50 entries per page)
- **Lazy loading** for dictionary viewer (large YAML files)
- **Debounced search** in template selector (300ms delay)

---

## Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

---

## Next Steps

1. **Review this specification** with UX team
2. **Create mock data files** (see ui-specs/mock-data/)
3. **Generate components** using Copilot
4. **Test with real CloudStack APIs** (integration phase)
5. **Iterate based on user feedback**

---

## References

- **Original Design:** `VNF_Framework_Design_CloudStack_4_21_7.txt`
- **API Spec:** `api-specs/vnf-api-spec.yaml`
- **CloudStack Primate:** https://github.com/apache/cloudstack-primate
- **Ant Design Vue:** https://antdv.com/components/overview

---

**Document Status:** Draft v1.0  
**Last Updated:** November 4, 2025  
**Author:** VNF Framework Team
