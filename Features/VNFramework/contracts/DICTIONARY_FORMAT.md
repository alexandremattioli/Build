# VNF Broker Dictionary Format (v1)

## Overview
Dictionaries define how the broker translates abstract commands into vendor-specific API calls. Each vendor has its own dictionary file (e.g., `pfsense.yaml`, `fortigate.yaml`).

## Dictionary Structure

```yaml
vendor: <vendor_name>
version: <dictionary_version>
baseUrl: <base_api_url_template>
auth:
  type: <api_key|basic|token>
  # Additional auth config fields
operations:
  <operation_name>:
    method: <HTTP_METHOD>
    path: <url_path_template>
    headers: {...}
    bodyTemplate: <jinja2_template_or_inline>
    successCondition: <jsonpath_or_status_code>
    responseMapping:
      id: <jsonpath_for_vendor_id>
      success: <jsonpath_for_success_flag>
      error: <jsonpath_for_error_message>
    retryable: <bool>
    idempotent: <bool>
```

## Placeholders
- `${var}`: Command field reference (e.g., `${interface}`, `${src.cidr}`)
- `${env.VAR}`: Environment variable (e.g., `${env.VNF_HOST}`)
- `${auth.token}`: Auth credential from broker config

## Example: pfSense Dictionary (excerpt)

```yaml
vendor: pfSense
version: 1.0.0
baseUrl: "https://${env.VNF_HOST}/api/v1"
auth:
  type: api_key
  keyHeader: "X-API-Key"
  keyEnv: "PFSENSE_API_KEY"
  clientIdEnv: "PFSENSE_CLIENT_ID"

operations:
  createFirewallRule:
    method: POST
    path: "/firewall/rules"
    headers:
      Content-Type: "application/json"
      X-API-Key: "${auth.apiKey}"
      X-Client-ID: "${auth.clientId}"
    bodyTemplate: |
      {
        "interface": "${interface}",
        "direction": "${direction}",
        "action": "${action}",
        "source": {
          {% if src.cidr %}
          "address": "${src.cidr}"
          {% elif src.alias %}
          "alias": "${src.alias}"
          {% endif %}
        },
        "destination": {
          {% if dst.cidr %}
          "address": "${dst.cidr}"
          {% elif dst.alias %}
          "alias": "${dst.alias}"
          {% endif %}
        },
        "protocol": "${protocol}",
        {% if ports %}
        "ports": {
          {% if ports.src %}"source": "${ports.src}",{% endif %}
          {% if ports.dst %}"destination": "${ports.dst}"{% endif %}
        },
        {% endif %}
        {% if description %}"description": "${description}",{% endif %}
        "enabled": ${enabled|default(true)},
        "log": ${log|default(false)}
      }
    successCondition:
      jsonPath: "$.status"
      equals: "success"
    responseMapping:
      id: "$.data.rule_id"
      vendorRef: "$.data.uuid"
      success: "$.status == 'success'"
      error: "$.error.message"
    retryable: false
    idempotent: true  # safe to retry if ruleId provided
    timeout: 10000  # ms

  getFirewallRule:
    method: GET
    path: "/firewall/rules/${ruleId}"
    headers:
      X-API-Key: "${auth.apiKey}"
      X-Client-ID: "${auth.clientId}"
    successCondition:
      statusCode: 200
    responseMapping:
      rule: "$.data"
      exists: "$.data != null"
    retryable: true
    idempotent: true
    timeout: 5000

  deleteFirewallRule:
    method: DELETE
    path: "/firewall/rules/${ruleId}"
    headers:
      X-API-Key: "${auth.apiKey}"
      X-Client-ID: "${auth.clientId}"
    successCondition:
      statusCode: [200, 204]
    responseMapping:
      success: "$.status == 'success' or response.status == 204"
      error: "$.error.message"
    retryable: false
    idempotent: true
    timeout: 8000
```

## Error Mapping
The broker maps vendor error responses to standard error codes:

| Vendor HTTP/Error | Broker Code | Retryable |
|-------------------|-------------|-----------|
| 401, 403 | VNF_AUTH | No |
| 408, 504, timeout | VNF_TIMEOUT | Yes |
| 409, "already exists" | VNF_CONFLICT | No |
| 400, "invalid..." | VNF_INVALID | No |
| 500, 502, 503 | VNF_UPSTREAM | Yes |
| Connection refused | VNF_UNREACHABLE | Yes |
| "quota exceeded" | VNF_CAPACITY | Yes (after delay) |

## Validation Rules
1. All `${...}` placeholders must reference valid command fields or env vars
2. `bodyTemplate` must produce valid JSON after substitution
3. JSONPath expressions in `responseMapping` must be valid
4. `successCondition` must be deterministic (no side effects)
5. `timeout` values should be < broker global timeout (20s)

## Testing
Each dictionary should have:
- Unit tests: placeholder substitution correctness
- Contract tests: validate generated payloads against vendor API docs
- Integration tests: mock vendor responses and verify mapping logic
