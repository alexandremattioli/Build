# Copilot Workflow: Generate VNF Framework Mock UI (Iterative in VS Code)

Date: 2025-11-04
Target: GitHub Copilot + Copilot Chat in VS Code
Output: Complete Vue 3 mock UI project ready to run

---

## Prerequisites

- VS Code with GitHub Copilot and Copilot Chat extensions
- Node.js 18+
- A clean folder for the UI project (separate from CloudStack repo)

---

## Open the context files in VS Code

Open these files side-by-side so Copilot can learn from them:

- `ui-specs/UI-DESIGN-SPECIFICATION.md`
- `ui-specs/COMPONENT-SPECIFICATIONS.md`
- `ui-specs/mock-data/vnf-mock-data.json`
- `api-specs/vnf-api-spec.yaml`

Tip: Pin them in the editor and keep them open while generating code.

---

## Step 1 — Create the project

In a terminal:

```powershell
npm create vite@latest vnf-framework-ui -- --template vue-ts
cd vnf-framework-ui
npm install
npm install ant-design-vue pinia vue-router date-fns js-yaml @ant-design/icons-vue
```

Open this new folder in VS Code.

---

## Step 2 — Generate types

Create a file `src/types/vnf.ts` and write a short comment to cue Copilot:

```typescript
// Generate TypeScript interfaces from ui-specs/mock-data/vnf-mock-data.json
// Include: VnfTemplate, VnfStatus, ConnectivityTestResult, AuditLogEntry, ReconciliationResults, ValidationResult
```

Accept Copilot's full suggestion and adjust as needed.

---

## Step 3 — Mock API service

Create `src/api/vnf.ts` with this cue:

```typescript
// Mock API service that reads data from /ui-specs/mock-data/vnf-mock-data.json
// Add 200–500ms delays and ~10% failure rate to simulate the network.
// Implement: listVnfTemplates, getVnfStatus, testVnfConnectivity, reconcileVnfNetwork, listVnfAuditLog,
// updateTemplateDictionary, validateDictionary.
```

Accept Copilot suggestions. Ensure imports and paths resolve.

---

## Step 4 — Pinia store

Create `src/store/vnf.ts`:

```typescript
// Pinia store for VNF: state (templates, status, audit), actions, getters
// Use vnfApi methods; handle loading and error states.
```

---

## Step 5 — Components (6 files)

Create the following files under `src/views/vnf/components/` and prompt Copilot with a header comment copied from the spec file (Purpose, Template Structure):

1) `VnfHealthCard.vue`
2) `VnfDictionaryUploader.vue`
3) `VnfConnectivityTest.vue`
4) `VnfTemplateSelector.vue`
5) `VnfAuditLog.vue`
6) `VnfReconciliation.vue`

Tip: For each, paste the relevant section from `COMPONENT-SPECIFICATIONS.md` at the top of the file to guide Copilot.

---

## Step 6 — Views (3 files)

Create under `src/views/vnf/`:

- `TemplateVnfConfig.vue` (uses VnfDictionaryUploader)
- `NetworkVnfStatus.vue` (uses VnfHealthCard + modals)
- `NetworkVnfSelection.vue` (uses VnfTemplateSelector)

Provide a short comment in each file describing which components to assemble and which routes to use.

---

## Step 7 — Router & App

Edit `src/router/index.ts`:

```typescript
// Add routes for VNF views with lazy loading and basic breadcrumbs
```

Edit `src/App.vue` to use Ant Design layout and navigation between VNF pages.

In `src/main.ts`, register Ant Design Vue, Pinia, and Router. Import Ant Design reset CSS:

```typescript
import 'ant-design-vue/dist/reset.css'
```

---

## Step 8 — Run the app

```powershell
npm run dev
```

Open the app and navigate to:

- `/vnf/networks/network-123/status` (healthy)
- `/vnf/networks/network-124/status` (degraded)
- `/vnf/networks/network-125/status` (unreachable)
- `/vnf/templates/template-001/config` (dictionary upload)

---

## Tips for better Copilot results

- Keep the spec files open in the editor and reference them in comments
- Start with the template sections, then ask Copilot for the script and styles
- If a suggestion is partial, write a small TODO and prompt again
- Use Copilot Chat: "Generate the script setup block for this component based on the spec above"

---

## Done — What to expect

- Functional mock UI with realistic data
- Health status, connectivity test modal, reconciliation modal, audit log
- Dictionary upload and validation interactions
- TypeScript types across the app

Next: integrate real CloudStack APIs by replacing the mock service in `src/api/vnf.ts`.
