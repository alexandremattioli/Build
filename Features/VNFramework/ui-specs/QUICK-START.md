# Generate VNF Framework UI with Copilot/Codex - Quick Start

**⏱️ Total Time:** 30-60 minutes to complete functional mock UI  
**🎯 Goal:** Generate a working Vue 3 UI that demonstrates all VNF Framework features

---

## 🚀 Fastest Path to Working UI

### Option 1: Use GitHub Copilot Workspace (Recommended)

1. **Open GitHub Copilot Workspace** in VS Code
2. **Paste this prompt:**

```
Create a complete Vue 3 mock UI for the VNF Framework feature in Apache CloudStack.

CONTEXT FILES (read these first):
- ui-specs/UI-DESIGN-SPECIFICATION.md
- ui-specs/COMPONENT-SPECIFICATIONS.md  
- ui-specs/mock-data/vnf-mock-data.json

TECH STACK:
- Vue 3 Composition API + TypeScript
- Ant Design Vue 4.x
- Pinia (state management)
- Vite (build tool)

GENERATE:
1. Complete project structure (package.json, vite.config.ts, tsconfig.json)
2. Type definitions (src/types/vnf.ts) from mock data
3. Mock API service (src/api/vnf.ts) returning JSON data with 200-500ms delays
4. Pinia store (src/store/vnf.ts) with actions and getters
5. 6 Vue components in src/views/vnf/components/:
   - VnfDictionaryUploader.vue (YAML upload/validation)
   - VnfHealthCard.vue (health monitoring with auto-refresh)
   - VnfConnectivityTest.vue (modal with step-by-step test)
   - VnfTemplateSelector.vue (template cards)
   - VnfAuditLog.vue (audit table with expandable rows)
   - VnfReconciliation.vue (reconciliation progress modal)
6. 3 page views in src/views/vnf/:
   - TemplateVnfConfig.vue (uses VnfDictionaryUploader)
   - NetworkVnfStatus.vue (uses VnfHealthCard, test/reconcile modals)
   - NetworkVnfSelection.vue (uses VnfTemplateSelector)
7. Router config (src/router/index.ts) with lazy loading
8. Main App.vue with Ant Design layout and navigation

REQUIREMENTS:
- Follow specs exactly (check COMPONENT-SPECIFICATIONS.md for each component)
- Use mock-data/vnf-mock-data.json for all API responses
- Include loading states and error handling
- Make it fully functional with realistic interactions
- Add comments explaining key sections
- Use formatDistanceToNow from date-fns for relative times

OUTPUT: Complete, working project ready to run with `npm install && npm run dev`
```

3. **Wait for generation** (5-10 minutes)
4. **Review and test** the generated code

---

### Option 2: Iterative with GitHub Copilot in VS Code

**Time:** 30-45 minutes  
**Best for:** More control over each step

#### Step 1: Create Project (5 min)

```bash
npm create vite@latest vnf-framework-ui -- --template vue-ts
cd vnf-framework-ui
npm install
npm install ant-design-vue pinia vue-router date-fns js-yaml @ant-design/icons-vue
```

#### Step 2: Generate Types (3 min)

Create `src/types/vnf.ts`:
```typescript
// Generate TypeScript interfaces from ui-specs/mock-data/vnf-mock-data.json
// Include: VnfTemplate, VnfStatus, ConnectivityTestResult, AuditLogEntry, etc.
```

Let Copilot suggest → Accept all

#### Step 3: Generate Mock API (5 min)

Create `src/api/vnf.ts`:
```typescript
// Mock API service using data from ui-specs/mock-data/vnf-mock-data.json
// Add 200-500ms delays with setTimeout
// Methods: listVnfTemplates, getVnfStatus, testVnfConnectivity, etc.
```

Let Copilot suggest → Accept all

#### Step 4: Generate Store (5 min)

Create `src/store/vnf.ts`:
```typescript
// Pinia store for VNF state management
// State: vnfTemplates, currentNetworkStatus, auditLog, loading states
// Actions: fetchVnfTemplates, fetchNetworkStatus, testConnectivity, reconcileNetwork
// Getters: vnfReadyTemplates
```

Let Copilot suggest → Accept all

#### Step 5: Generate Components (15 min, ~2-3 min each)

For each component, create file and let Copilot generate based on COMPONENT-SPECIFICATIONS.md:

1. `src/views/vnf/components/VnfHealthCard.vue`
2. `src/views/vnf/components/VnfDictionaryUploader.vue`
3. `src/views/vnf/components/VnfConnectivityTest.vue`
4. `src/views/vnf/components/VnfTemplateSelector.vue`
5. `src/views/vnf/components/VnfAuditLog.vue`
6. `src/views/vnf/components/VnfReconciliation.vue`

For each file:
```vue
<!-- ComponentName.vue - see ui-specs/COMPONENT-SPECIFICATIONS.md -->
<!-- [Paste the Purpose and Template Structure sections from spec] -->
```

Let Copilot generate the full component

#### Step 6: Generate Views (5 min)

Create 3 page views:
- `src/views/vnf/TemplateVnfConfig.vue`
- `src/views/vnf/NetworkVnfStatus.vue`
- `src/views/vnf/NetworkVnfSelection.vue`

#### Step 7: Router & App (2 min)

Update `src/router/index.ts` and `src/App.vue`

---

## 👀 How they can show you the mock UI

You have three simple options to view the generated mock UI:

1. Vite dev server (recommended for full project)
   - Run: `npm run dev`
   - Open: <http://localhost:5173>
2. Static demo page (no build tools)
   - Open: <http://localhost:8085>
   - If not running, start it by running the included static server:
     - From VS Code terminal: PowerShell (Windows)
     - Command: `powershell -ExecutionPolicy Bypass -File "VNF_Implementation/ui-specs/demo/Start-StaticServer.ps1" -Port 8085`
3. GitHub Pages (shareable link)
   - Build the mock UI (`npm run build`) and push the `dist/` folder to a `gh-pages` branch
   - Enable GitHub Pages in repo settings and share the URL

---

## 🧪 Test the Generated UI

```bash
npm run dev
# Open http://localhost:5173
```

### Test Scenarios

Navigate to these URLs and verify functionality:

1. **Healthy Network Status**
   - URL: `/vnf/networks/network-123/status`
   - Expected: Green "Healthy" badge, 12/12 rules, 45ms latency
   - Click "Test Connectivity" → All tests pass

2. **Degraded Network Status**
   - URL: `/vnf/networks/network-124/status`
   - Expected: Yellow "Degraded" badge, 9/12 rules, drift warning
   - Click "Reconcile Now" → Shows progress and fixes drift

3. **Unreachable Network Status**
   - URL: `/vnf/networks/network-125/status`
   - Expected: Red "Unreachable" badge, connectivity error
   - Click "Test Connectivity" → Shows failure with troubleshooting

4. **Template Dictionary Upload**
   - URL: `/vnf/templates/template-001/config`
   - Expected: Upload form, validation, version history
   - Paste YAML from `dictionaries/pfsense-dictionary.yaml` → Validates successfully

---

## [i] Checklist

After generation, verify:

- [ ] Project runs without errors (`npm run dev`)
- [ ] All 6 components render correctly
- [ ] Navigation works between views
- [ ] Mock data displays (templates, status, audit log)
- [ ] Loading states show during "API calls"
- [ ] Health card shows different states (healthy/degraded/unreachable)
- [ ] Test connectivity modal works with step-by-step progress
- [ ] Reconciliation modal shows phases and results
- [ ] Audit log table expands rows to show details
- [ ] Dictionary uploader validates YAML
- [ ] Template selector shows VNF-ready templates
- [ ] TypeScript compiles without errors
- [ ] Responsive on mobile (test with DevTools)

---

## 🎨 Customize

After generation, you can:

### Change Theme Colors

```scss
// src/styles/variables.scss
$primary-color: #1890ff;
$success-color: #52c41a;
$warning-color: #faad14;
$error-color: #f5222d;
```

### Add More Mock Data

Edit `ui-specs/mock-data/vnf-mock-data.json`:
- Add more templates
- Add different network scenarios
- Add more audit log entries

### Adjust API Delays

```typescript
// src/api/vnf.ts
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))

// Change from 200-500ms to faster:
await delay(100) // Faster for demo
```

### Add Real API Integration

```typescript
// src/api/vnf.ts
import axios from 'axios'

export const vnfApi = {
  async listVnfTemplates() {
    // Replace mock data with real API call:
    const response = await axios.get('/api/v1/listVnfTemplates')
    return response.data.templates
  }
}
```

---

## 🐛 Troubleshooting

### "Cannot find module '@/types/vnf'"

**Fix:** Check `vite.config.ts` has alias:
```typescript
export default {
  resolve: {
    alias: {
      '@': '/src'
    }
  }
}
```

### "Ant Design components not rendering"

**Fix:** Import Ant Design CSS in `main.ts`:
```typescript
import 'ant-design-vue/dist/reset.css'
```

### "formatDistanceToNow is not a function"

**Fix:** Install date-fns:
```bash
npm install date-fns
```

### TypeScript errors in components

**Fix:** Generate types first before components. Make sure:
```typescript
// src/types/vnf.ts is complete with all interfaces
export interface VnfTemplate { ... }
export interface VnfStatus { ... }
// etc.
```

---

## 📦 Next Steps

Once you have the working mock UI:

1. **Demo to stakeholders** - Show the UI to get feedback
2. **Refine based on feedback** - Adjust layouts, flows
3. **Add unit tests** (optional but recommended):
   ```bash
   npm install -D vitest @vue/test-utils
   ```
4. **Deploy to GitHub Pages** for easy sharing:
   ```bash
   npm run build
   # Deploy dist/ to GitHub Pages
   ```
5. **Integrate with real APIs** - Replace mock service with CloudStack API calls
6. **Merge into CloudStack Primate** - Copy components to Primate codebase

---

## 📚 Reference

- **Full UI Spec:** `ui-specs/UI-DESIGN-SPECIFICATION.md` (40 pages)
- **Component Details:** `ui-specs/COMPONENT-SPECIFICATIONS.md` (30 pages)
- **Mock Data:** `ui-specs/mock-data/vnf-mock-data.json` (600 lines)
- **Detailed Guide:** `ui-specs/COPILOT-GENERATION-GUIDE.md` (50 pages)

---

## ⏱️ Time Estimates

| Method | Time | Result |
|--------|------|--------|
| Copilot Workspace (Option 1) | 10-15 min | Complete project |
| Iterative Copilot (Option 2) | 30-45 min | Complete project |
| Manual coding (no AI) | 2-3 weeks | Same result |

**Time saved with AI: 95%+** 🚀

---

**Ready? Start with Option 1 for fastest results!**
