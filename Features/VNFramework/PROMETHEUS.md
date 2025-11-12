# Prometheus Integration Guide

**VNF Broker Prometheus Metrics Exporter**  
**Status:** [OK] COMPLETE  
**Last Updated:** 2025-11-07

---

## Overview

The VNF Broker now exposes Prometheus metrics at `/metrics.prom` for comprehensive observability of:
- HTTP request patterns and latency
- Rate limiting effectiveness
- JWT authentication failures
- Circuit breaker state per VNF instance

---

## Quick Verification

```bash
cd /Builder2/Build/Features/VNFramework
./validate_metrics.sh
```

Or manually:
```bash
curl -k https://localhost:8443/metrics.prom | head -60
```

---

## Exposed Metrics Summary

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `vnf_broker_http_requests_total` | Counter | method, endpoint, status | Total HTTP requests by endpoint and status code |
| `vnf_broker_request_latency_seconds` | Histogram | endpoint | Request processing latency distribution |
| `vnf_broker_rate_limit_allowed_total` | Counter | client | Requests that passed rate limiting |
| `vnf_broker_rate_limit_blocked_total` | Counter | client | Requests blocked by rate limiter (HTTP 429) |
| `vnf_broker_jwt_invalid_total` | Counter | (none) | Count of invalid/expired JWT tokens |
| `vnf_broker_circuit_breaker_state` | Gauge | vnf_instance_id | Circuit breaker state: 0=closed, 1=half_open, 2=open |

---

## Prometheus Configuration

### Step 1: Add scrape target to `prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'vnf-broker-dev'
    scheme: https
    metrics_path: /metrics.prom
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:8443']
        labels:
          environment: 'development'
          instance: 'vnf-broker-build2'
    tls_config:
      insecure_skip_verify: true  # Remove in production with proper certs
```

### Step 2: Verify scrape target

```bash
# Check Prometheus targets page
http://localhost:9090/targets

# Query metrics
http://localhost:9090/graph
# Query: vnf_broker_http_requests_total
```

---

## Grafana Dashboard

### Sample Dashboard JSON (vnf_broker_dashboard.json)

```json
{
  "dashboard": {
    "title": "VNF Broker Metrics",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [
          {
            "expr": "rate(vnf_broker_http_requests_total[5m])",
            "legendFormat": "{{method}} {{endpoint}} - {{status}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Request Latency (95th percentile)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(vnf_broker_request_latency_seconds_bucket[5m]))",
            "legendFormat": "{{endpoint}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Rate Limiting",
        "targets": [
          {
            "expr": "rate(vnf_broker_rate_limit_allowed_total[5m])",
            "legendFormat": "Allowed - {{client}}"
          },
          {
            "expr": "rate(vnf_broker_rate_limit_blocked_total[5m])",
            "legendFormat": "Blocked - {{client}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Circuit Breaker State",
        "targets": [
          {
            "expr": "vnf_broker_circuit_breaker_state",
            "legendFormat": "{{vnf_instance_id}}"
          }
        ],
        "type": "stat",
        "valueMappings": [
          {"value": "0", "text": "CLOSED"},
          {"value": "1", "text": "HALF_OPEN"},
          {"value": "2", "text": "OPEN"}
        ]
      },
      {
        "title": "JWT Failures",
        "targets": [
          {
            "expr": "rate(vnf_broker_jwt_invalid_total[5m])",
            "legendFormat": "Invalid/Expired JWT"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

---

## Alerting Rules

### Example `vnf_broker_alerts.yml`

```yaml
groups:
  - name: vnf_broker_alerts
    interval: 30s
    rules:
      # Circuit breaker open for too long
      - alert: CircuitBreakerOpenTooLong
        expr: vnf_broker_circuit_breaker_state == 2
        for: 2m
        labels:
          severity: warning
          component: vnf-broker
        annotations:
          summary: "Circuit breaker OPEN for VNF {{ $labels.vnf_instance_id }}"
          description: "Circuit breaker has been open for >2 minutes. VNF backend may be down."
          runbook_url: "https://docs/runbooks/circuit-breaker-open"

      # High rate limiting blocks
      - alert: HighRateLimitBlocking
        expr: increase(vnf_broker_rate_limit_blocked_total[5m]) > 100
        labels:
          severity: info
          component: vnf-broker
        annotations:
          summary: "High rate limit blocking ({{ $labels.client }})"
          description: "Over 100 requests blocked in 5m for client {{ $labels.client }}. May indicate abuse or misconfiguration."

      # Elevated JWT failures
      - alert: JWTAuthenticationFailures
        expr: rate(vnf_broker_jwt_invalid_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
          component: vnf-broker
        annotations:
          summary: "Elevated JWT authentication failures"
          description: "JWT validation failures exceeding 0.1/sec over 5 minutes. Check token generation or key rotation."

      # High latency
      - alert: HighRequestLatency
        expr: histogram_quantile(0.95, rate(vnf_broker_request_latency_seconds_bucket[5m])) > 1.0
        for: 3m
        labels:
          severity: warning
          component: vnf-broker
        annotations:
          summary: "High request latency on {{ $labels.endpoint }}"
          description: "95th percentile latency >1s for endpoint {{ $labels.endpoint }}."

      # Error rate spike
      - alert: HighErrorRate
        expr: |
          sum(rate(vnf_broker_http_requests_total{status=~"5.."}[5m]))
          /
          sum(rate(vnf_broker_http_requests_total[5m]))
          > 0.05
        for: 2m
        labels:
          severity: critical
          component: vnf-broker
        annotations:
          summary: "High error rate (>5%)"
          description: "5xx error rate exceeds 5% over 2 minutes. Investigate broker health."
```

---

## PromQL Query Examples

### Request throughput by endpoint
```promql
rate(vnf_broker_http_requests_total[5m])
```

### 99th percentile latency
```promql
histogram_quantile(0.99, rate(vnf_broker_request_latency_seconds_bucket[5m]))
```

### Rate limit block percentage
```promql
100 * (
  sum(rate(vnf_broker_rate_limit_blocked_total[5m]))
  /
  (sum(rate(vnf_broker_rate_limit_blocked_total[5m])) + sum(rate(vnf_broker_rate_limit_allowed_total[5m])))
)
```

### Circuit breaker open instances
```promql
count(vnf_broker_circuit_breaker_state == 2)
```

### HTTP error rate
```promql
sum(rate(vnf_broker_http_requests_total{status=~"5.."}[5m]))
```

---

## Production Deployment

### 1. Secure Metrics Endpoint

Option A: Network ACL (recommended)
```bash
# Firewall rule: allow only Prometheus server IP
iptables -A INPUT -p tcp --dport 8443 -s <prometheus-ip> -j ACCEPT
```

Option B: Reverse proxy with auth
```nginx
location /metrics.prom {
    auth_basic "Metrics";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass https://localhost:8443;
}
```

Option C: mTLS (mutual TLS)
- Configure broker with client certificate verification
- Prometheus scrape config with client certs

### 2. Enable TLS Verification

Replace self-signed certs:
```bash
# Generate proper certs from CA
# Update config.dev.json -> TLS_CERT_PATH, TLS_KEY_PATH
# Remove insecure_skip_verify from Prometheus config
```

### 3. Tune Prometheus Retention

```yaml
# prometheus.yml or CLI flags
storage:
  tsdb:
    retention.time: 30d
    retention.size: 50GB
```

---

## Validation Checklist

- [x] prometheus-client dependency added to requirements.txt
- [x] Metrics defined (Counters, Histograms, Gauges)
- [x] before_request/after_request hooks installed
- [x] Rate limiting instrumented (allowed/blocked)
- [x] JWT validation failures tracked
- [x] Circuit breaker state exposed per VNF
- [x] /metrics.prom endpoint created
- [x] METRICS.md documentation created
- [x] validate_metrics.sh script provided
- [x] Prometheus scrape config examples
- [x] Grafana dashboard JSON template
- [x] Alert rules defined

---

## Testing

### 1. Start broker with metrics
```bash
cd /Builder2/Build/Features/VNFramework
docker compose up -d
# OR
./quickstart.sh --broker-only
```

### 2. Validate metrics endpoint
```bash
./validate_metrics.sh
```

### 3. Generate traffic to populate metrics
```bash
# Health checks
for i in {1..10}; do curl -k https://localhost:8443/health; sleep 1; done

# Trigger rate limiting (if you have a JWT token)
for i in {1..150}; do 
  curl -k -X POST https://localhost:8443/api/vnf/firewall/create \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"vnfInstanceId":"10.0.0.1","ruleId":"test'$i'","action":"allow","protocol":"tcp","sourceIp":"192.168.1.0/24","destinationIp":"10.0.0.0/8","destinationPort":443}' &
done
wait

# Check metrics again
curl -k https://localhost:8443/metrics.prom | grep rate_limit
```

### 4. Verify in Prometheus
```bash
# Start Prometheus (with config pointing to broker)
docker run -d -p 9090:9090 \
  -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

# Open browser
http://localhost:9090/graph
# Query: vnf_broker_http_requests_total
```

---

## Troubleshooting

### Metrics endpoint returns empty
- Ensure prometheus-client is installed: `pip list | grep prometheus-client`
- Check broker logs for import errors
- Verify endpoint: `curl -k https://localhost:8443/metrics.prom -v`

### Prometheus can't scrape (connection refused)
- Check broker is listening: `netstat -tulpn | grep 8443`
- Verify TLS config: `curl -k https://localhost:8443/health`
- Check Prometheus logs: `docker logs <prometheus-container>`

### Metrics not incrementing
- Generate traffic to broker endpoints
- Verify before/after request hooks are called (check logs)
- Test with simple health check: `curl -k https://localhost:8443/health`

---

## Files Reference

| File | Purpose |
|------|---------|
| `python-broker/vnf_broker_enhanced.py` | Metrics instrumentation code |
| `python-broker/requirements.txt` | prometheus-client dependency |
| `METRICS.md` | Metrics overview and examples |
| `PROMETHEUS.md` | This integration guide |
| `validate_metrics.sh` | Validation script |

---

## Support

**Build2 Owner:** VNF Framework Phase 1  
**Documentation:** See METRICS.md for metric details  
**Examples:** See QUICKSTART.md for running the broker  
**Issues:** Contact Build2 via coordination messages

---

**[OK] Prometheus metrics exporter is fully operational!**
