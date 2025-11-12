# Copilot/Codex Guide: Generate VNF Framework Mock UI

**Goal:** Use GitHub Copilot or OpenAI Codex to generate a complete, functional mock UI for the VNF Framework feature in Apache CloudStack Primate.

---

## Prerequisites

### 1. Files You Need to Load
Place these files in your context (open in VS Code):

- [OK] `UI-DESIGN-SPECIFICATION.md` - Screen layouts and user flows
- [OK] `COMPONENT-SPECIFICATIONS.md` - Vue component details
- [OK] `mock-data/vnf-mock-data.json` - Sample API responses
- [OK] `../api-specs/vnf-api-spec.yaml` - API contracts
- [OK] `../VNF_Framework_Design_CloudStack_4_21_7.txt` - Original design document (optional, for context)

### 2. CloudStack Primate Context
Copilot needs to understand existing Primate patterns. Open these example files:

```
cloudstack-primate/src/views/network/
  ├── CreateNetwork.vue      (network wizard example)
  ├── NetworkDetails.vue     (network details page)
  └── FirewallRules.vue      (firewall rules table)

cloudstack-primate/src/views/infra/
  └── TemplateDetails.vue    (template details with tabs)
```

### 3. Tech Stack
- **Vue 3** with Composition API
- **Ant Design Vue 4.x**
- **TypeScript**
- **Vite** (build tool)
- **Pinia** or **Vuex** (state management)

---

## Step-by-Step Generation Process

### Phase 1: Set Up Project Structure

**Copilot Prompt:**
```
Create a Vue 3 + Vite project structure for VNF Framework UI mock.

Requirements:
- Vue 3 with TypeScript
- Ant Design Vue
- Router with routes for VNF screens
- Pinia store for state management
- Mock API service using JSON data

Generate:
1. package.json with all dependencies
2. vite.config.ts
3. tsconfig.json
4. Directory structure: src/views/vnf/, src/api/, src/store/, src/types/
```

**Expected Output:**
```
vnf-framework-ui-mock/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── index.html
└── src/
    ├── main.ts
    ├── App.vue
    ├── router/
    │   └── index.ts
    ├── store/
    │   └── vnf.ts
    ├── api/
    │   └── vnf.ts
    ├── types/
    │   └── vnf.ts
    ├── views/
    │   └── vnf/
    │       ├── TemplateVnfConfig.vue
    │       ├── NetworkVnfSelection.vue
    │       ├── NetworkVnfStatus.vue
    │       └── components/
    └── assets/
```

---

### Phase 2: Generate Type Definitions

**Copilot Prompt:**
```typescript
// src/types/vnf.ts
// Generate TypeScript interfaces based on mock-data/vnf-mock-data.json

// Include interfaces for:
// - VnfTemplate
// - VnfStatus
// - ConnectivityTest
// - AuditLogEntry
// - ReconciliationResults
// - ValidationResult
// - DictionaryVersion

// Make sure all fields from the JSON are properly typed
```

**Expected Output:**
```typescript
export interface VnfTemplate {
  id: string
  name: string
  vendor: string
  version: string
  vnfReady: boolean
  apiType: 'REST' | 'XML' | 'SSH'
  services: string[]
  dictionary: {
    version: string
    lastUpdated: string
    metadata: Record<string, any>
  }
  description: string
}

export interface VnfStatus {
  networkId: string
  healthStatus: 'healthy' | 'degraded' | 'unreachable'
  connectivity: boolean
  syncedRules: number
  totalRules: number
  lastReconcile: string
  apiLatency: number
  vnfDetails: {
    name: string
    template: string
    managementIp: string
    dictionary: string
    broker: string
  }
  driftCount: number
  driftDetails: string[]
}

// ... more interfaces
```

---

### Phase 3: Generate Mock API Service

**Copilot Prompt:**
```typescript
// src/api/vnf.ts
// Create a mock API service that returns data from mock-data/vnf-mock-data.json

// Import the mock data
import mockData from '@/mock-data/vnf-mock-data.json'

// Implement these methods:
// - listVnfTemplates(): Promise<VnfTemplate[]>
// - getVnfStatus(networkId: string): Promise<VnfStatus>
// - testVnfConnectivity(networkId: string): Promise<ConnectivityTestResult>
// - reconcileVnfNetwork(networkId: string): Promise<ReconciliationResults>
// - listVnfAuditLog(networkId: string): Promise<AuditLogEntry[]>
// - updateTemplateDictionary(templateId: string, dictionary: any): Promise<void>
// - validateDictionary(dictionary: any): Promise<ValidationResult>

// Add realistic delays (200-500ms) using setTimeout
// Randomly return error state (10% of the time) for testing
```

**Expected Output:**
```typescript
import type { VnfTemplate, VnfStatus, ConnectivityTestResult } from '@/types/vnf'
import mockData from '@/mock-data/vnf-mock-data.json'

const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))
const shouldFail = () => Math.random() < 0.1 // 10% failure rate

export const vnfApi = {
  async listVnfTemplates(): Promise<VnfTemplate[]> {
    await delay(300)
    if (shouldFail()) throw new Error('Failed to load templates')
    return mockData.templates
  },

  async getVnfStatus(networkId: string): Promise<VnfStatus> {
    await delay(200)
    if (shouldFail()) throw new Error('Failed to get status')
    
    // Return different statuses based on networkId
    if (networkId === 'network-124') return mockData.vnfStatusDegraded
    if (networkId === 'network-125') return mockData.vnfStatusUnreachable
    return mockData.vnfStatus
  },

  // ... more methods
}
```

---

### Phase 4: Generate Pinia Store

**Copilot Prompt:**
```typescript
// src/store/vnf.ts
// Create a Pinia store for VNF state management

// State should include:
// - vnfTemplates: VnfTemplate[]
// - currentNetworkStatus: VnfStatus | null
// - auditLog: AuditLogEntry[]
// - loading states for each operation

// Actions should include:
// - fetchVnfTemplates()
// - fetchNetworkStatus(networkId: string)
// - testConnectivity(networkId: string)
// - reconcileNetwork(networkId: string)
// - fetchAuditLog(networkId: string)

// Use the vnfApi service
```

**Expected Output:**
```typescript
import { defineStore } from 'pinia'
import { vnfApi } from '@/api/vnf'
import type { VnfTemplate, VnfStatus, AuditLogEntry } from '@/types/vnf'

export const useVnfStore = defineStore('vnf', {
  state: () => ({
    vnfTemplates: [] as VnfTemplate[],
    currentNetworkStatus: null as VnfStatus | null,
    auditLog: [] as AuditLogEntry[],
    isLoadingTemplates: false,
    isLoadingStatus: false,
    isLoadingAuditLog: false
  }),

  actions: {
    async fetchVnfTemplates() {
      this.isLoadingTemplates = true
      try {
        this.vnfTemplates = await vnfApi.listVnfTemplates()
      } catch (error) {
        console.error('Failed to fetch templates:', error)
        throw error
      } finally {
        this.isLoadingTemplates = false
      }
    },

    // ... more actions
  },

  getters: {
    vnfReadyTemplates: (state) => {
      return state.vnfTemplates.filter(t => t.vnfReady)
    }
  }
})
```

---

### Phase 5: Generate Vue Components

#### 5.1 VnfDictionaryUploader Component

**Copilot Prompt:**
```vue
<!-- src/views/vnf/components/VnfDictionaryUploader.vue -->
<!-- 
Generate a complete Vue 3 component for uploading VNF dictionaries.

Requirements from COMPONENT-SPECIFICATIONS.md:
- Upload mode: file upload OR paste YAML
- Real-time validation with results display
- Current dictionary info display
- Version history table with rollback
- Uses Ant Design Vue components: a-card, a-upload, a-textarea, a-alert, a-table

Follow the template structure in COMPONENT-SPECIFICATIONS.md exactly.
Use Composition API with TypeScript.
Import vnfApi for API calls.
-->
```

**Copilot will generate the full component based on the specification.**

#### 5.2 VnfHealthCard Component

**Copilot Prompt:**
```vue
<!-- src/views/vnf/components/VnfHealthCard.vue -->
<!-- 
Generate a complete Vue 3 component for displaying VNF health status.

Requirements from COMPONENT-SPECIFICATIONS.md:
- Health indicator with color-coded badge
- Metrics grid: connectivity, rules in sync, last reconcile, API latency
- VNF details descriptions
- Action buttons: test connectivity, reconcile, view audit log
- Drift detection alert with auto-fix option
- Auto-refresh every 60 seconds

Use Composition API with TypeScript.
Import useVnfStore for state management.
Use formatDistanceToNow from date-fns for relative time.
-->
```

#### 5.3 VnfConnectivityTest Component

**Copilot Prompt:**
```vue
<!-- src/views/vnf/components/VnfConnectivityTest.vue -->
<!-- 
Generate a modal component for VNF connectivity testing.

Requirements from COMPONENT-SPECIFICATIONS.md:
- Modal with progress indicator
- 6 test steps with status icons
- Show results with metrics or errors
- Troubleshooting recommendations for failures
- Run Again button

Use a-modal, a-progress, a-list, a-result from Ant Design Vue.
Simulate step-by-step execution with delays.
-->
```

#### 5.4 Remaining Components

Generate similarly:
- `VnfTemplateSelector.vue` - Template selection cards
- `VnfAuditLog.vue` - Audit log table with expandable rows
- `VnfReconciliation.vue` - Reconciliation progress modal

---

### Phase 6: Generate Page Views

#### 6.1 Template VNF Configuration Tab

**Copilot Prompt:**
```vue
<!-- src/views/vnf/TemplateVnfConfig.vue -->
<!-- 
Generate a page view that uses VnfDictionaryUploader component.

This is a tab in the template details page.
Shows:
- VNF Ready badge
- Dictionary uploader component
- Current dictionary info
- Version history

Route: /template/:id/vnf-config
-->
```

#### 6.2 Network VNF Status Card

**Copilot Prompt:**
```vue
<!-- src/views/vnf/NetworkVnfStatus.vue -->
<!-- 
Generate a page view that uses VnfHealthCard component.

This is shown in the network details page.
Includes:
- VnfHealthCard component
- VnfConnectivityTest modal (opened on button click)
- VnfReconciliation modal (opened on button click)
- VnfAuditLog in collapsible section

Route: /network/:id/vnf-status
-->
```

---

### Phase 7: Generate Router Configuration

**Copilot Prompt:**
```typescript
// src/router/index.ts
// Generate Vue Router configuration for VNF views

// Routes needed:
// - /vnf/templates/:id/config - Template VNF configuration
// - /vnf/networks/:id/status - Network VNF status
// - /vnf/networks/create - Network creation with VNF selection

// Use lazy loading for components
// Add route meta for breadcrumbs
```

---

### Phase 8: Generate Main App

**Copilot Prompt:**
```vue
<!-- src/App.vue -->
<!-- 
Generate the main App component with:
- Ant Design layout (a-layout)
- Header with navigation
- Sidebar with menu items:
  - VNF Templates
  - VNF Networks
- Router view for content
- Global styles
-->
```

---

## Complete Copilot Workflow

### Option A: Generate All at Once (Recommended for Codex)

**Single Large Prompt:**
```
Generate a complete Vue 3 mock UI for VNF Framework based on these specifications:

Context Files:
1. UI-DESIGN-SPECIFICATION.md - Defines all screens and layouts
2. COMPONENT-SPECIFICATIONS.md - Defines Vue component structure
3. mock-data/vnf-mock-data.json - Sample API responses
4. api-specs/vnf-api-spec.yaml - API contracts

Requirements:
- Vue 3 Composition API with TypeScript
- Ant Design Vue 4.x components
- Pinia for state management
- Mock API service using provided JSON data
- 6 main components: VnfDictionaryUploader, VnfHealthCard, VnfConnectivityTest, VnfTemplateSelector, VnfAuditLog, VnfReconciliation
- 3 page views: TemplateVnfConfig, NetworkVnfStatus, NetworkVnfSelection
- Router with lazy loading
- Responsive design
- Error handling with try/catch and error messages

Output Structure:
vnf-framework-ui-mock/
├── src/
│   ├── types/vnf.ts
│   ├── api/vnf.ts
│   ├── store/vnf.ts
│   ├── router/index.ts
│   ├── views/vnf/
│   │   ├── components/
│   │   │   ├── VnfDictionaryUploader.vue
│   │   │   ├── VnfHealthCard.vue
│   │   │   ├── VnfConnectivityTest.vue
│   │   │   ├── VnfTemplateSelector.vue
│   │   │   ├── VnfAuditLog.vue
│   │   │   └── VnfReconciliation.vue
│   │   ├── TemplateVnfConfig.vue
│   │   ├── NetworkVnfStatus.vue
│   │   └── NetworkVnfSelection.vue
│   ├── App.vue
│   └── main.ts
├── package.json
├── vite.config.ts
└── tsconfig.json

Make it functional with realistic interactions, not just static UI.
Follow CloudStack Primate patterns for consistency.
Add comments explaining key sections.
```

---

### Option B: Iterative Generation (Recommended for Copilot in VS Code)

Use GitHub Copilot in VS Code with this workflow:

1. **Create file**: `src/types/vnf.ts`
   - Type: `// Generate TypeScript interfaces from mock-data/vnf-mock-data.json`
   - Let Copilot suggest the entire interface structure
   - Accept and review

2. **Create file**: `src/api/vnf.ts`
   - Type: `// Mock API service using mock data with delays`
   - Copilot will suggest based on types
   - Accept and adjust delays

3. **Create file**: `src/store/vnf.ts`
   - Type: `// Pinia store for VNF state management`
   - Copilot suggests based on API service
   - Accept and add any missing actions

4. **Create file**: `src/views/vnf/components/VnfHealthCard.vue`
   - Type: `<!-- VNF Health Status Card - see COMPONENT-SPECIFICATIONS.md -->`
   - Copilot suggests entire component structure
   - Accept and refine

5. **Repeat for all components and views**

---

## Testing the Generated UI

### Run the Mock UI

```bash
cd vnf-framework-ui-mock
npm install
npm run dev
```

### Test Scenarios

**1. Template Dictionary Upload**
- Navigate to `/vnf/templates/template-001/config`
- Paste sample YAML from `dictionaries/pfsense-dictionary.yaml`
- Click "Validate" - should show success
- Click "Save Dictionary" - should save and show in version history

**2. Network VNF Status - Healthy**
- Navigate to `/vnf/networks/network-123/status`
- Should show green "Healthy" badge
- All metrics should be positive (12/12 rules, 45ms latency)
- Click "Test Connectivity" - all tests should pass

**3. Network VNF Status - Degraded**
- Navigate to `/vnf/networks/network-124/status`
- Should show yellow "Degraded" badge
- Should show "3 rules out of sync"
- Click "Reconcile Now" - should show reconciliation progress

**4. Network VNF Status - Unreachable**
- Navigate to `/vnf/networks/network-125/status`
- Should show red "Unreachable" badge
- Click "Test Connectivity" - should show failure with troubleshooting tips

**5. Audit Log**
- Navigate to network status page
- Click "View Audit Log"
- Should show 7 log entries
- Click any row - should expand with request/response details

---

## Customization After Generation

### Add Real API Integration (Later)

Replace mock API service:

```typescript
// src/api/vnf.ts
import { axios } from '@/utils/request'

export const vnfApi = {
  async listVnfTemplates() {
    const response = await axios.get('/api/vnf/templates')
    return response.data.templates
  },
  // ... replace all mock methods with real API calls
}
```

### Add Authentication

```typescript
// src/api/vnf.ts
import { getToken } from '@/utils/auth'

const createAuthHeaders = () => ({
  headers: {
    'Authorization': `Bearer ${getToken()}`
  }
})

export const vnfApi = {
  async listVnfTemplates() {
    return axios.get('/api/vnf/templates', createAuthHeaders())
  }
}
```

### Deploy with CloudStack Primate

1. Copy generated components to CloudStack Primate:
   ```bash
   cp -r src/views/vnf/ cloudstack-primate/src/views/infra/
   ```

2. Update routes in Primate:
   ```typescript
   // cloudstack-primate/src/router/index.ts
   {
     path: '/template/:id/vnf',
     component: () => import('@/views/infra/vnf/TemplateVnfConfig.vue')
   }
   ```

3. Replace mock API with CloudStack API calls

---

## Expected Completion Time

- **Codex (single large prompt)**: 5-10 minutes
- **Copilot (iterative)**: 30-60 minutes
- **Manual customization**: 1-2 hours
- **Integration with real APIs**: 2-4 hours
- **Total**: 4-6 hours for fully functional mock UI

---

## Success Criteria

[OK] All 6 components render without errors  
[OK] Navigation between views works  
[OK] Mock data displays correctly  
[OK] Loading states show during API calls  
[OK] Error states display with messages  
[OK] Responsive design works on mobile  
[OK] TypeScript compiles without errors  
[OK] All user flows from UI-DESIGN-SPECIFICATION.md are functional  

---

## Troubleshooting

### Issue: Copilot not generating full components

**Solution:** Break down into smaller prompts:
```
// Step 1: Template structure only
<!-- Generate <template> section for VnfHealthCard -->

// Step 2: Script section
// Generate <script setup> for VnfHealthCard with Composition API

// Step 3: Styles
// Generate <style scoped> for VnfHealthCard
```

### Issue: TypeScript errors

**Solution:** Generate types first, then components. Make sure:
- All imports are correct
- Types are exported from `src/types/vnf.ts`
- Mock data matches type definitions

### Issue: Mock data not loading

**Solution:** Check import path and Vite config:
```typescript
// vite.config.ts
export default {
  resolve: {
    alias: {
      '@': '/src'
    }
  },
  json: {
    stringify: false // Allow importing JSON as objects
  }
}
```

---

## Next Steps After Generation

1. **Review generated code** for correctness
2. **Test all user flows** from UI specification
3. **Add unit tests** (optional, but recommended)
4. **Deploy to GitHub Pages** for demo
5. **Integrate with real CloudStack APIs**
6. **Get feedback** from stakeholders
7. **Iterate and refine** based on feedback

---

## Resources

- **Vue 3 Docs**: https://vuejs.org/guide/
- **Ant Design Vue**: https://antdv.com/components/overview
- **Pinia**: https://pinia.vuejs.org/
- **Vite**: https://vitejs.dev/guide/
- **CloudStack Primate**: https://github.com/apache/cloudstack-primate

---

**Ready to generate!** 🚀

Start with Option A (single large prompt) for fastest results, or Option B (iterative) for more control.
