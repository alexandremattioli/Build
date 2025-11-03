# Codex Workflow: Generate VNF Framework Mock UI (Single-Prompt, End-to-End)

Date: 2025-11-04
Target: OpenAI Codex / Code models in OpenAI Playground or API
Output: Complete Vue 3 mock UI project ready to run

---

## What you'll get

- Full Vue 3 + TypeScript + Vite project
- Ant Design Vue integrated
- Pinia store, router, API mock service
- 6 fully functional components
- 3 page views wired to routes
- Uses realistic mock data from JSON

---

## Preparation (Playground)

1) Go to OpenAI Playground
2) Model: A current Code-capable model (e.g., GPT-4.1, GPT-4.1-mini, or similar)
3) Mode: Chat
4) Upload the following files (use the + Attach button):
   - ui-specs/UI-DESIGN-SPECIFICATION.md
   - ui-specs/COMPONENT-SPECIFICATIONS.md
   - ui-specs/mock-data/vnf-mock-data.json
   - api-specs/vnf-api-spec.yaml

5) System message (paste):

```text
You are a senior Vue 3 + Ant Design Vue engineer. Produce complete, runnable code with TypeScript and high-quality structure. Follow CloudStack Primate style conventions when applicable. Favor clarity and correctness.
```

---

## Single master prompt (paste as User)


```text
Generate a complete Vue 3 mock UI for the VNF Framework feature in Apache CloudStack.

Use the attached files as the authoritative specifications:
- UI-DESIGN-SPECIFICATION.md  (wireframes, flows, layouts)
- COMPONENT-SPECIFICATIONS.md (component structure, props/emits/methods)
- vnf-mock-data.json          (realistic mock API responses)
- vnf-api-spec.yaml           (API contracts)

Requirements:
- Vue 3 + Vite + TypeScript
- Ant Design Vue 4.x
- Pinia (state)
- Vue Router with lazy-loaded routes
- API: use mock service reading vnf-mock-data.json with 200–500ms delays and 10% error chance
- Components (6): VnfDictionaryUploader, VnfHealthCard, VnfConnectivityTest, VnfTemplateSelector, VnfAuditLog, VnfReconciliation
- Views (3): TemplateVnfConfig, NetworkVnfStatus, NetworkVnfSelection
- Types in src/types/vnf.ts derived from vnf-mock-data.json
- Comments explaining key logic
- Error and loading states for all network calls
- Responsive layout

Project structure:
- package.json, vite.config.ts, tsconfig.json
- src/
  - main.ts, App.vue
  - router/index.ts
  - store/vnf.ts
  - api/vnf.ts
  - types/vnf.ts
  - views/vnf/
    - components/
      - VnfDictionaryUploader.vue
      - VnfHealthCard.vue
      - VnfConnectivityTest.vue
      - VnfTemplateSelector.vue
      - VnfAuditLog.vue
      - VnfReconciliation.vue
    - TemplateVnfConfig.vue
    - NetworkVnfStatus.vue
    - NetworkVnfSelection.vue

Acceptance criteria:
- Compiles with `npm install && npm run dev`
- Navigable routes
- Health card shows healthy/degraded/unreachable using provided mock data
- Connectivity modal shows step-by-step progress and results
- Reconciliation modal shows phases and changes
- Audit log table expands rows with request/response samples
- Dictionary uploader validates and displays results from mock endpoints
- TypeScript types match mock data fields

Deliver:
- Print all files with proper paths and contents, ready to save to disk.
- Keep each file in its own fenced block labeled with its path.
```

---

## Optional follow-ups

- Ask for a ZIP of the generated project
- Ask for unit tests using Vitest and Vue Test Utils
- Ask for a GitHub Actions workflow to lint/build

---

## Run locally (after saving files)

```powershell
npm install
npm run dev
```

Open <http://localhost:5173> and use the test URLs suggested in UI-DESIGN-SPECIFICATION.md.
