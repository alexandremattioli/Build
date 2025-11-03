# VNF Framework Vue.js Component Specifications

**Target Framework:** Vue 3 Composition API + Ant Design Vue  
**CloudStack Version:** 4.21.7 Primate UI  
**Date:** November 4, 2025

---

## Component Architecture

```
src/views/infra/vnf/
├── components/
│   ├── VnfDictionaryUploader.vue
│   ├── VnfTemplateSelector.vue
│   ├── VnfHealthCard.vue
│   ├── VnfConnectivityTest.vue
│   ├── VnfAuditLog.vue
│   └── VnfReconciliation.vue
├── TemplateVnfConfig.vue      (Tab in template details)
├── NetworkVnfSelection.vue     (Section in network wizard)
└── NetworkVnfStatus.vue        (Card in network details)
```

---

## 1. VnfDictionaryUploader.vue

### Purpose
Upload and validate YAML dictionaries for VNF templates

### Template Structure
```vue
<template>
  <div class="vnf-dictionary-uploader">
    <a-card title="Upload Dictionary" :loading="isLoading">
      <!-- Upload Mode Selector -->
      <a-radio-group v-model:value="uploadMode" class="upload-mode">
        <a-radio-button value="file">Upload YAML File</a-radio-button>
        <a-radio-button value="paste">Paste YAML Content</a-radio-button>
      </a-radio-group>

      <!-- File Upload Mode -->
      <div v-if="uploadMode === 'file'" class="upload-section">
        <a-upload
          :before-upload="handleFileUpload"
          :file-list="fileList"
          accept=".yaml,.yml"
        >
          <a-button>
            <upload-outlined /> Choose File
          </a-button>
        </a-upload>
      </div>

      <!-- Paste Mode -->
      <div v-else class="paste-section">
        <a-textarea
          v-model:value="yamlContent"
          :rows="15"
          placeholder="Paste YAML dictionary content here..."
          class="yaml-editor"
          @change="debouncedValidate"
        />
      </div>

      <!-- Validation Results -->
      <a-alert
        v-if="validationResults.length > 0"
        :type="validationType"
        :message="validationMessage"
        class="validation-results"
        show-icon
      >
        <template #description>
          <ul class="validation-list">
            <li
              v-for="(result, index) in validationResults"
              :key="index"
              :class="result.level"
            >
              <check-circle-outlined v-if="result.level === 'success'" />
              <warning-outlined v-if="result.level === 'warning'" />
              <close-circle-outlined v-if="result.level === 'error'" />
              {{ result.message }}
            </li>
          </ul>
        </template>
      </a-alert>

      <!-- Action Buttons -->
      <div class="actions">
        <a-button
          @click="validateDictionary"
          :loading="isValidating"
          :disabled="!yamlContent"
        >
          Validate
        </a-button>
        <a-button
          type="primary"
          @click="saveDictionary"
          :loading="isSaving"
          :disabled="!isValid || !yamlContent"
        >
          Save Dictionary
        </a-button>
      </div>
    </a-card>

    <!-- Current Dictionary Info (if exists) -->
    <a-card
      v-if="currentDictionary"
      title="Current Dictionary Info"
      class="current-dictionary"
    >
      <a-descriptions :column="2">
        <a-descriptions-item label="Vendor">
          {{ currentDictionary.metadata.vendor }}
        </a-descriptions-item>
        <a-descriptions-item label="Version">
          {{ currentDictionary.metadata.version }}
        </a-descriptions-item>
        <a-descriptions-item label="API Type">
          {{ currentDictionary.metadata.api_type }}
        </a-descriptions-item>
        <a-descriptions-item label="Authentication">
          {{ currentDictionary.authentication.type }}
        </a-descriptions-item>
      </a-descriptions>

      <a-divider />

      <h4>Supported Services</h4>
      <a-space wrap>
        <a-tag
          v-for="service in dictionaryServices"
          :key="service"
          color="blue"
        >
          {{ service }}
        </a-tag>
      </a-space>

      <div class="dictionary-actions">
        <a-button @click="viewFullDictionary">
          <eye-outlined /> View Full Dictionary
        </a-button>
        <a-button @click="downloadDictionary">
          <download-outlined /> Download YAML
        </a-button>
      </div>
    </a-card>

    <!-- Version History -->
    <a-card title="Dictionary Version History" class="version-history">
      <a-table
        :columns="historyColumns"
        :data-source="versionHistory"
        :pagination="{ pageSize: 10 }"
        :loading="isLoadingHistory"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'actions'">
            <a-space>
              <a-button size="small" @click="viewVersion(record)">
                View
              </a-button>
              <a-popconfirm
                title="Rollback to this version?"
                @confirm="rollbackVersion(record)"
              >
                <a-button size="small" danger>
                  Rollback
                </a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>
    </a-card>
  </div>
</template>
```

### Script (Composition API)
```typescript
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { message } from 'ant-design-vue'
import { debounce } from 'lodash-es'
import yaml from 'js-yaml'
import api from '@/api'

// Props
const props = defineProps<{
  templateId: string
  existingDictionary?: object
}>()

// Emits
const emit = defineEmits<{
  'dictionary-uploaded': [dictionary: object]
  'validation-complete': [results: ValidationResult[]]
  'save-complete': [success: boolean]
}>()

// State
const uploadMode = ref<'file' | 'paste'>('paste')
const yamlContent = ref('')
const fileList = ref([])
const validationResults = ref<ValidationResult[]>([])
const isLoading = ref(false)
const isValidating = ref(false)
const isSaving = ref(false)
const currentDictionary = ref(props.existingDictionary)
const versionHistory = ref([])
const isLoadingHistory = ref(false)

// Computed
const isValid = computed(() => {
  return validationResults.value.every(r => r.level !== 'error')
})

const validationType = computed(() => {
  if (validationResults.value.some(r => r.level === 'error')) return 'error'
  if (validationResults.value.some(r => r.level === 'warning')) return 'warning'
  return 'success'
})

const validationMessage = computed(() => {
  if (validationType.value === 'error') return 'Dictionary has errors'
  if (validationType.value === 'warning') return 'Dictionary valid with warnings'
  return 'Dictionary is valid'
})

const dictionaryServices = computed(() => {
  if (!currentDictionary.value?.services) return []
  return Object.keys(currentDictionary.value.services)
})

// Table columns
const historyColumns = [
  { title: 'Version', dataIndex: 'version', key: 'version' },
  { title: 'Date', dataIndex: 'date', key: 'date' },
  { title: 'Updated By', dataIndex: 'updatedBy', key: 'updatedBy' },
  { title: 'Actions', key: 'actions' }
]

// Methods
const handleFileUpload = (file: File) => {
  const reader = new FileReader()
  reader.onload = (e) => {
    yamlContent.value = e.target?.result as string
    validateDictionary()
  }
  reader.readAsText(file)
  return false // Prevent auto upload
}

const validateDictionary = async () => {
  if (!yamlContent.value) return

  isValidating.value = true
  try {
    // Parse YAML
    const parsed = yaml.load(yamlContent.value)
    
    // Call API to validate
    const response = await api.vnf.validateDictionary({
      templateId: props.templateId,
      dictionary: parsed
    })

    validationResults.value = response.results
    emit('validation-complete', response.results)

  } catch (error: any) {
    validationResults.value = [{
      level: 'error',
      message: `YAML parsing error: ${error.message}`
    }]
  } finally {
    isValidating.value = false
  }
}

const debouncedValidate = debounce(validateDictionary, 500)

const saveDictionary = async () => {
  if (!isValid.value) {
    message.error('Please fix validation errors before saving')
    return
  }

  isSaving.value = true
  try {
    const parsed = yaml.load(yamlContent.value)
    
    await api.vnf.updateTemplateDictionary({
      templateId: props.templateId,
      dictionary: parsed
    })

    message.success('Dictionary saved successfully')
    currentDictionary.value = parsed
    emit('save-complete', true)
    loadVersionHistory()

  } catch (error: any) {
    message.error(`Save failed: ${error.message}`)
    emit('save-complete', false)
  } finally {
    isSaving.value = false
  }
}

const loadVersionHistory = async () => {
  isLoadingHistory.value = true
  try {
    const response = await api.vnf.listDictionaryVersions({
      templateId: props.templateId
    })
    versionHistory.value = response.versions
  } catch (error) {
    console.error('Failed to load version history', error)
  } finally {
    isLoadingHistory.value = false
  }
}

const viewVersion = (version: any) => {
  // TODO: Open modal with version details
  console.log('View version', version)
}

const rollbackVersion = async (version: any) => {
  try {
    await api.vnf.rollbackDictionary({
      templateId: props.templateId,
      versionId: version.id
    })
    message.success(`Rolled back to version ${version.version}`)
    loadVersionHistory()
  } catch (error: any) {
    message.error(`Rollback failed: ${error.message}`)
  }
}

const viewFullDictionary = () => {
  // TODO: Open modal with full dictionary
  console.log('View full dictionary')
}

const downloadDictionary = () => {
  const yamlStr = yaml.dump(currentDictionary.value)
  const blob = new Blob([yamlStr], { type: 'text/yaml' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `dictionary-${props.templateId}.yaml`
  a.click()
}

// Lifecycle
onMounted(() => {
  if (currentDictionary.value) {
    yamlContent.value = yaml.dump(currentDictionary.value)
  }
  loadVersionHistory()
})

// Types
interface ValidationResult {
  level: 'success' | 'warning' | 'error'
  message: string
}
</script>
```

### Styles
```scss
<style lang="scss" scoped>
.vnf-dictionary-uploader {
  .upload-mode {
    margin-bottom: 16px;
  }

  .yaml-editor {
    font-family: 'Monaco', 'Menlo', 'Courier New', monospace;
    font-size: 12px;
  }

  .validation-results {
    margin: 16px 0;

    .validation-list {
      margin: 0;
      padding-left: 20px;

      li {
        margin: 4px 0;

        &.success { color: #52c41a; }
        &.warning { color: #faad14; }
        &.error { color: #f5222d; }
      }
    }
  }

  .actions {
    display: flex;
    gap: 8px;
    margin-top: 16px;
  }

  .current-dictionary,
  .version-history {
    margin-top: 16px;
  }

  .dictionary-actions {
    margin-top: 16px;
    display: flex;
    gap: 8px;
  }
}
</style>
```

---

## 2. VnfHealthCard.vue

### Purpose
Display VNF appliance health status and provide quick actions

### Template Structure
```vue
<template>
  <a-card
    title="VNF Appliance Status"
    class="vnf-health-card"
    :loading="isLoading"
  >
    <template #extra>
      <a-button
        size="small"
        @click="refreshStatus"
        :loading="isRefreshing"
      >
        <reload-outlined /> Refresh
      </a-button>
    </template>

    <!-- Health Indicator -->
    <div class="health-indicator">
      <a-badge :status="healthBadgeStatus" :text="healthText" />
      <span class="last-check">Last check: {{ lastCheckTime }}</span>
    </div>

    <!-- Metrics Grid -->
    <a-row :gutter="16" class="metrics-grid">
      <a-col :span="6">
        <a-statistic
          title="Connectivity"
          :value="connectivity ? 'Online' : 'Offline'"
          :value-style="{ color: connectivity ? '#3f8600' : '#cf1322' }"
        >
          <template #prefix>
            <api-outlined v-if="connectivity" />
            <disconnect-outlined v-else />
          </template>
        </a-statistic>
      </a-col>

      <a-col :span="6">
        <a-statistic
          title="Rules in Sync"
          :value="`${syncedRules} / ${totalRules}`"
          :value-style="{ color: allInSync ? '#3f8600' : '#faad14' }"
        >
          <template #prefix>
            <check-circle-outlined v-if="allInSync" />
            <warning-outlined v-else />
          </template>
        </a-statistic>
      </a-col>

      <a-col :span="6">
        <a-statistic
          title="Last Reconcile"
          :value="lastReconcileTime"
        >
          <template #prefix>
            <sync-outlined />
          </template>
        </a-statistic>
      </a-col>

      <a-col :span="6">
        <a-statistic
          title="API Latency"
          :value="apiLatency"
          suffix="ms"
          :value-style="{ color: latencyColor }"
        >
          <template #prefix>
            <thunderbolt-outlined />
          </template>
        </a-statistic>
      </a-col>
    </a-row>

    <!-- VNF Details -->
    <a-descriptions :column="2" size="small" class="vnf-details">
      <a-descriptions-item label="Name">
        {{ vnfDetails.name }}
      </a-descriptions-item>
      <a-descriptions-item label="Template">
        {{ vnfDetails.template }}
      </a-descriptions-item>
      <a-descriptions-item label="Management IP">
        {{ vnfDetails.managementIp }}
      </a-descriptions-item>
      <a-descriptions-item label="Dictionary">
        {{ vnfDetails.dictionary }}
      </a-descriptions-item>
      <a-descriptions-item label="Broker">
        {{ vnfDetails.broker }}
      </a-descriptions-item>
    </a-descriptions>

    <!-- Action Buttons -->
    <div class="actions">
      <a-button @click="testConnectivity">
        <experiment-outlined /> Test Connectivity
      </a-button>
      <a-button type="primary" @click="reconcileNow">
        <sync-outlined /> Reconcile Now
      </a-button>
      <a-button @click="viewAuditLog">
        <file-text-outlined /> View Audit Log
      </a-button>
    </div>

    <!-- Drift Detection -->
    <a-alert
      v-if="driftCount > 0"
      type="warning"
      :message="`${driftCount} rules out of sync`"
      class="drift-alert"
      show-icon
    >
      <template #description>
        <ul class="drift-list">
          <li v-for="(drift, index) in driftDetails" :key="index">
            {{ drift }}
          </li>
        </ul>
        <a-space>
          <a-button size="small" @click="autoFixRules">
            Auto-Fix Rules
          </a-button>
          <a-button size="small" @click="viewDriftDetails">
            View Details
          </a-button>
        </a-space>
      </template>
    </a-alert>

    <a-alert
      v-else-if="!isLoading"
      type="success"
      message="All rules in sync"
      class="drift-alert"
      show-icon
    />
  </a-card>
</template>
```

### Script
```typescript
<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { message } from 'ant-design-vue'
import { formatDistanceToNow } from 'date-fns'
import api from '@/api'

// Props
const props = defineProps<{
  networkId: string
  refreshInterval?: number // milliseconds
}>()

// Emits
const emit = defineEmits<{
  'test-connectivity': []
  'reconcile-now': []
  'view-audit-log': []
}>()

// State
const isLoading = ref(true)
const isRefreshing = ref(false)
const healthStatus = ref<'healthy' | 'degraded' | 'unreachable'>('healthy')
const connectivity = ref(true)
const syncedRules = ref(12)
const totalRules = ref(12)
const lastReconcile = ref(new Date())
const apiLatency = ref(45)
const vnfDetails = ref({
  name: '',
  template: '',
  managementIp: '',
  dictionary: '',
  broker: ''
})
const driftCount = ref(0)
const driftDetails = ref<string[]>([])
const lastCheck = ref(new Date())
let refreshTimer: NodeJS.Timer | null = null

// Computed
const healthBadgeStatus = computed(() => {
  return {
    healthy: 'success',
    degraded: 'warning',
    unreachable: 'error'
  }[healthStatus.value]
})

const healthText = computed(() => {
  return {
    healthy: 'Healthy',
    degraded: 'Degraded',
    unreachable: 'Unreachable'
  }[healthStatus.value]
})

const lastCheckTime = computed(() => {
  return formatDistanceToNow(lastCheck.value, { addSuffix: true })
})

const lastReconcileTime = computed(() => {
  return formatDistanceToNow(lastReconcile.value, { addSuffix: true })
})

const allInSync = computed(() => {
  return syncedRules.value === totalRules.value
})

const latencyColor = computed(() => {
  if (apiLatency.value < 100) return '#3f8600'
  if (apiLatency.value < 300) return '#faad14'
  return '#cf1322'
})

// Methods
const fetchStatus = async () => {
  try {
    const response = await api.vnf.getVnfStatus({
      networkId: props.networkId
    })

    healthStatus.value = response.healthStatus
    connectivity.value = response.connectivity
    syncedRules.value = response.syncedRules
    totalRules.value = response.totalRules
    lastReconcile.value = new Date(response.lastReconcile)
    apiLatency.value = response.apiLatency
    vnfDetails.value = response.vnfDetails
    driftCount.value = response.driftCount
    driftDetails.value = response.driftDetails || []
    lastCheck.value = new Date()

  } catch (error: any) {
    message.error(`Failed to fetch status: ${error.message}`)
    healthStatus.value = 'unreachable'
  } finally {
    isLoading.value = false
    isRefreshing.value = false
  }
}

const refreshStatus = () => {
  isRefreshing.value = true
  fetchStatus()
}

const testConnectivity = () => {
  emit('test-connectivity')
}

const reconcileNow = () => {
  emit('reconcile-now')
}

const viewAuditLog = () => {
  emit('view-audit-log')
}

const autoFixRules = async () => {
  try {
    await api.vnf.reconcileVnfNetwork({
      networkId: props.networkId,
      autoFix: true
    })
    message.success('Auto-fix initiated')
    setTimeout(fetchStatus, 2000)
  } catch (error: any) {
    message.error(`Auto-fix failed: ${error.message}`)
  }
}

const viewDriftDetails = () => {
  // TODO: Open modal with drift details
  console.log('View drift details')
}

const startAutoRefresh = () => {
  const interval = props.refreshInterval || 60000 // default 1 minute
  refreshTimer = setInterval(fetchStatus, interval)
}

const stopAutoRefresh = () => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
    refreshTimer = null
  }
}

// Lifecycle
onMounted(() => {
  fetchStatus()
  startAutoRefresh()
})

onUnmounted(() => {
  stopAutoRefresh()
})
</script>
```

### Styles
```scss
<style lang="scss" scoped>
.vnf-health-card {
  .health-indicator {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 24px;
    font-size: 16px;

    .last-check {
      color: #8c8c8c;
      font-size: 12px;
    }
  }

  .metrics-grid {
    margin-bottom: 24px;
  }

  .vnf-details {
    margin-bottom: 16px;
  }

  .actions {
    display: flex;
    gap: 8px;
    margin-bottom: 16px;
  }

  .drift-alert {
    .drift-list {
      margin: 8px 0;
      padding-left: 20px;

      li {
        margin: 4px 0;
      }
    }
  }
}
</style>
```

---

## 3. VnfConnectivityTest.vue

### Purpose
Run and display connectivity test results

### Template Structure
```vue
<template>
  <a-modal
    v-model:open="visible"
    title="Test VNF Connectivity"
    :footer="null"
    width="600px"
    class="vnf-connectivity-test"
  >
    <div v-if="isRunning" class="test-progress">
      <p>Testing connectivity to {{ vnfName }}...</p>
      
      <a-progress
        :percent="progress"
        :status="progressStatus"
        :stroke-color="progressColor"
      />

      <a-list :data-source="testSteps" class="test-steps">
        <template #renderItem="{ item }">
          <a-list-item>
            <a-list-item-meta>
              <template #avatar>
                <loading-outlined v-if="item.status === 'running'" spin />
                <check-circle-outlined
                  v-else-if="item.status === 'success'"
                  style="color: #52c41a"
                />
                <close-circle-outlined
                  v-else-if="item.status === 'failed'"
                  style="color: #f5222d"
                />
                <clock-circle-outlined v-else style="color: #d9d9d9" />
              </template>
              <template #title>{{ item.title }}</template>
              <template #description>
                {{ item.description }}
              </template>
            </a-list-item-meta>
          </a-list-item>
        </template>
      </a-list>
    </div>

    <div v-else-if="testComplete" class="test-results">
      <a-result
        :status="allTestsPassed ? 'success' : 'error'"
        :title="allTestsPassed ? 'All Tests Passed' : 'Connectivity Test Failed'"
      >
        <template #subTitle>
          <div v-if="allTestsPassed">
            All connectivity tests completed successfully
          </div>
          <div v-else>
            Some tests failed. See details below.
          </div>
        </template>

        <template #extra>
          <a-space>
            <a-button @click="closeModal">Close</a-button>
            <a-button v-if="!allTestsPassed" type="primary" @click="viewLogs">
              View Logs
            </a-button>
            <a-button @click="runTest">Run Again</a-button>
          </a-space>
        </template>
      </a-result>

      <!-- Test Steps Results -->
      <a-list :data-source="testSteps" class="test-steps">
        <template #renderItem="{ item }">
          <a-list-item>
            <a-list-item-meta>
              <template #avatar>
                <check-circle-outlined
                  v-if="item.status === 'success'"
                  style="color: #52c41a"
                />
                <close-circle-outlined
                  v-else-if="item.status === 'failed'"
                  style="color: #f5222d"
                />
              </template>
              <template #title>{{ item.title }}</template>
              <template #description>
                <div>{{ item.description }}</div>
                <div v-if="item.error" class="error-details">
                  <strong>Error:</strong> {{ item.error }}
                  <div v-if="item.troubleshooting" class="troubleshooting">
                    <strong>Troubleshooting:</strong>
                    <ul>
                      <li v-for="(tip, idx) in item.troubleshooting" :key="idx">
                        {{ tip }}
                      </li>
                    </ul>
                  </div>
                </div>
              </template>
            </a-list-item-meta>
          </a-list-item>
        </template>
      </a-list>

      <!-- Metrics -->
      <a-card v-if="allTestsPassed" title="Connectivity Metrics" size="small">
        <a-descriptions :column="3" size="small">
          <a-descriptions-item label="Round-trip Latency">
            {{ metrics.totalLatency }}ms
          </a-descriptions-item>
          <a-descriptions-item label="Broker Latency">
            {{ metrics.brokerLatency }}ms
          </a-descriptions-item>
          <a-descriptions-item label="API Latency">
            {{ metrics.apiLatency }}ms
          </a-descriptions-item>
        </a-descriptions>
      </a-card>
    </div>
  </a-modal>
</template>
```

### Script
```typescript
<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { message } from 'ant-design-vue'
import api from '@/api'

// Props
const props = defineProps<{
  networkId: string
  vnfApplianceId: string
  vnfName: string
  modelValue: boolean
}>()

// Emits
const emit = defineEmits<{
  'update:modelValue': [value: boolean]
  'test-complete': [success: boolean]
  'test-failed': [error: string]
}>()

// State
const visible = ref(props.modelValue)
const isRunning = ref(false)
const testComplete = ref(false)
const progress = ref(0)
const testSteps = ref<TestStep[]>([
  { id: 1, title: 'VNF VM Status', description: '', status: 'pending' },
  { id: 2, title: 'Broker Reachability', description: '', status: 'pending' },
  { id: 3, title: 'JWT Token Validation', description: '', status: 'pending' },
  { id: 4, title: 'VNF API Response', description: '', status: 'pending' },
  { id: 5, title: 'Authentication Test', description: '', status: 'pending' },
  { id: 6, title: 'Test Rule Creation', description: '', status: 'pending' }
])
const metrics = ref({
  totalLatency: 0,
  brokerLatency: 0,
  apiLatency: 0
})

// Computed
const progressStatus = computed(() => {
  if (!testComplete.value) return 'active'
  return allTestsPassed.value ? 'success' : 'exception'
})

const progressColor = computed(() => {
  if (!testComplete.value) return '#1890ff'
  return allTestsPassed.value ? '#52c41a' : '#f5222d'
})

const allTestsPassed = computed(() => {
  return testSteps.value.every(step => step.status === 'success')
})

// Watch
watch(() => props.modelValue, (newVal) => {
  visible.value = newVal
  if (newVal) {
    runTest()
  }
})

watch(visible, (newVal) => {
  emit('update:modelValue', newVal)
})

// Methods
const runTest = async () => {
  isRunning.value = true
  testComplete.value = false
  progress.value = 0
  
  // Reset steps
  testSteps.value.forEach(step => {
    step.status = 'pending'
    step.description = ''
    step.error = undefined
    step.troubleshooting = undefined
  })

  try {
    const response = await api.vnf.testVnfConnectivity({
      networkId: props.networkId
    })

    // Simulate step-by-step execution
    for (let i = 0; i < testSteps.value.length; i++) {
      const step = testSteps.value[i]
      step.status = 'running'
      
      await new Promise(resolve => setTimeout(resolve, 500)) // Simulate delay
      
      const stepResult = response.steps[i]
      step.status = stepResult.success ? 'success' : 'failed'
      step.description = stepResult.description
      
      if (!stepResult.success) {
        step.error = stepResult.error
        step.troubleshooting = stepResult.troubleshooting
      }
      
      progress.value = ((i + 1) / testSteps.value.length) * 100
    }

    if (response.success) {
      metrics.value = response.metrics
      message.success('Connectivity test passed')
      emit('test-complete', true)
    } else {
      message.error('Connectivity test failed')
      emit('test-complete', false)
    }

  } catch (error: any) {
    message.error(`Test failed: ${error.message}`)
    emit('test-failed', error.message)
  } finally {
    isRunning.value = false
    testComplete.value = true
  }
}

const closeModal = () => {
  visible.value = false
}

const viewLogs = () => {
  // TODO: Open logs viewer
  console.log('View logs')
}

// Types
interface TestStep {
  id: number
  title: string
  description: string
  status: 'pending' | 'running' | 'success' | 'failed'
  error?: string
  troubleshooting?: string[]
}
</script>
```

---

## Remaining Components

Due to length constraints, here are the key specifications for the remaining components:

### 4. VnfTemplateSelector.vue
- **Purpose:** Select VNF template during network creation
- **Key Features:** Template cards with metadata, dictionary overrides, credential input
- **API Calls:** `listTemplates`, `getTemplateDictionary`

### 5. VnfAuditLog.vue
- **Purpose:** Display audit trail of all VNF operations
- **Key Features:** Filterable table, expandable rows, export to CSV
- **API Calls:** `listVnfAuditLog`

### 6. VnfReconciliation.vue
- **Purpose:** Run and display reconciliation results
- **Key Features:** Multi-phase progress, diff viewer, auto-fix option
- **API Calls:** `reconcileVnfNetwork`, `getReconciliationStatus`

---

## API Service (api/vnf.js)

```typescript
import { axios } from '@/utils/request'

export default {
  // Dictionary Management
  updateTemplateDictionary(params) {
    return axios.post('/vnf/updateTemplateDictionary', params)
  },
  
  validateDictionary(params) {
    return axios.post('/vnf/validateDictionary', params)
  },
  
  listDictionaryVersions(params) {
    return axios.get('/vnf/listDictionaryVersions', { params })
  },

  // VNF Status
  getVnfStatus(params) {
    return axios.get('/vnf/getStatus', { params })
  },
  
  testVnfConnectivity(params) {
    return axios.post('/vnf/testConnectivity', params)
  },

  // Reconciliation
  reconcileVnfNetwork(params) {
    return axios.post('/vnf/reconcile', params)
  },
  
  getReconciliationStatus(params) {
    return axios.get('/vnf/reconciliationStatus', { params })
  },

  // Audit Log
  listVnfAuditLog(params) {
    return axios.get('/vnf/auditLog', { params })
  }
}
```

---

## Vuex Store Module (store/modules/vnf.js)

```typescript
export default {
  namespaced: true,
  
  state: {
    vnfTemplates: [],
    currentNetwork: null,
    healthStatus: null,
    auditLog: []
  },
  
  mutations: {
    SET_VNF_TEMPLATES(state, templates) {
      state.vnfTemplates = templates
    },
    SET_HEALTH_STATUS(state, status) {
      state.healthStatus = status
    },
    SET_AUDIT_LOG(state, log) {
      state.auditLog = log
    }
  },
  
  actions: {
    async fetchVnfTemplates({ commit }) {
      const response = await api.vnf.listTemplates()
      commit('SET_VNF_TEMPLATES', response.templates)
    },
    
    async fetchHealthStatus({ commit }, networkId) {
      const response = await api.vnf.getVnfStatus({ networkId })
      commit('SET_HEALTH_STATUS', response)
    }
  },
  
  getters: {
    vnfReadyTemplates: state => {
      return state.vnfTemplates.filter(t => t.vnfReady)
    }
  }
}
```

---

## Copilot Generation Prompt

```
Generate complete Vue 3 components for VNF Framework UI based on:
1. UI-DESIGN-SPECIFICATION.md (wireframes)
2. COMPONENT-SPECIFICATIONS.md (this file)
3. mock-data/*.json (API responses)

Requirements:
- Vue 3 Composition API with TypeScript
- Ant Design Vue components
- Follow CloudStack Primate patterns
- Include error handling and loading states
- Add responsive design
- Include unit tests (*.spec.ts)

Output structure:
src/views/infra/vnf/
  components/
    VnfDictionaryUploader.vue
    VnfHealthCard.vue
    VnfConnectivityTest.vue
    VnfTemplateSelector.vue
    VnfAuditLog.vue
    VnfReconciliation.vue
```
