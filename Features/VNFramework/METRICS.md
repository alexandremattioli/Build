# VNF Broker Metrics (Prometheus)

**Status:** Initial instrumentation added (2025-11-07)  
**Endpoints:**
- JSON summary: `/metrics` (existing)
- Prometheus exposition: `/metrics.prom`

---

## Exposed Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `vnf_broker_http_requests_total` | Counter | method, endpoint, status | Total HTTP requests processed |
| `vnf_broker_request_latency_seconds` | Histogram | endpoint | Request latency (seconds) per endpoint |
| `vnf_broker_rate_limit_allowed_total` | Counter | client | Requests allowed by rate limiter |
| `vnf_broker_rate_limit_blocked_total` | Counter | client | Requests blocked (HTTP 429) |
| `vnf_broker_jwt_invalid_total` | Counter | (none) | Invalid or expired JWT tokens encountered |
| `vnf_broker_circuit_breaker_state` | Gauge | vnf_instance_id | Circuit breaker state (0=closed,1=half_open,2=open) |

---

## Usage

### Scrape Configuration (Prometheus `prometheus.yml`)
```yaml
scrape_configs:
  - job_name: 'vnf-broker'
    scheme: https
    metrics_path: /metrics.prom
    static_configs:
      - targets: ['broker-host.example.com:8443']
    tls_config:
      insecure_skip_verify: true  # remove when proper certs enabled
```

### Basic Curl
```bash
curl -k https://localhost:8443/metrics.prom | head -40
```

### Example Output (Excerpt)
```
# HELP vnf_broker_http_requests_total Total HTTP requests
# TYPE vnf_broker_http_requests_total counter
vnf_broker_http_requests_total{method="GET",endpoint="/health",status="200"} 5
vnf_broker_http_requests_total{method="POST",endpoint="/api/vnf/firewall/create",status="201"} 1
# HELP vnf_broker_request_latency_seconds Request latency in seconds
# TYPE vnf_broker_request_latency_seconds histogram
vnf_broker_request_latency_seconds_bucket{endpoint="/health",le="0.005"} 5
...
# HELP vnf_broker_circuit_breaker_state Circuit breaker state (0=closed,1=half_open,2=open)
# TYPE vnf_broker_circuit_breaker_state gauge
vnf_broker_circuit_breaker_state{vnf_instance_id="10.0.0.1"} 0
```

---

## Circuit Breaker State Mapping
| State | Gauge Value |
|-------|-------------|
| closed | 0 |
| half_open | 1 |
| open | 2 |

---

## Extension Ideas (Phase 2)
- Add `vnf_broker_request_bytes` (Histogram) for payload size
- Add `vnf_broker_backend_latency_seconds` per VNF instance
- Export Redis connection pool stats (custom collector)
- Add counter for idempotency cache hits vs misses
- Add labeled error counter splitting 4xx vs 5xx classes
- Integrate with Alertmanager (circuit breaker open rate > threshold)

---

## Alert Examples
```yaml
groups:
  - name: vnf-broker-alerts
    rules:
      - alert: CircuitBreakerOpenTooLong
        expr: vnf_broker_circuit_breaker_state == 2
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: Circuit breaker open >2m ({{ $labels.vnf_instance_id }})
          description: "VNF instance circuit breaker has remained OPEN for more than 2 minutes. Investigate backend availability."

      - alert: HighRateLimitBlocks
        expr: increase(vnf_broker_rate_limit_blocked_total[5m]) > 100
        labels:
          severity: info
        annotations:
          summary: High rate limit blocks
          description: Over 100 requests blocked in 5m window.
```

---

## Operational Notes
- Metrics are best-effort; failures in metric recording never impact request flow.
- `/metrics.prom` should be protected (mTLS or network ACL) in production.
- Histogram buckets use defaults; tune based on observed latency distribution during load tests.
- Self-signed certs in dev require `insecure_skip_verify: true` for Prometheus; remove once proper TLS deployed.

---

## Validation Checklist
- [x] Added dependency `prometheus-client` in `requirements.txt`
- [x] Instrumented request lifecycle (before/after request)
- [x] Added counters for rate limiting decisions
- [x] Added gauge for circuit breaker per VNF instance
- [x] Added JWT invalid counter
- [x] Exposed `/metrics.prom` endpoint

---

**Owner:** Build2  
**Next Review:** During Phase 2 performance tuning
