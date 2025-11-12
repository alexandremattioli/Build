#!/bin/bash
###############################################################################
# Prometheus Metrics Validation Script
# Demonstrates that /metrics.prom is working and exporting all metrics
###############################################################################

echo "=========================================="
echo "VNF Broker Prometheus Metrics Validator"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

BROKER_URL="https://localhost:8443"
METRICS_ENDPOINT="${BROKER_URL}/metrics.prom"

# Check if broker is running
echo -e "${BLUE}[1/5]${NC} Checking if broker is running..."
if curl -sk "${BROKER_URL}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Broker is responding at ${BROKER_URL}"
else
    echo -e "${RED}✗${NC} Broker not responding. Start it first:"
    echo "      cd /Builder2/Build/Features/VNFramework"
    echo "      ./quickstart.sh --broker-only"
    echo "      OR"
    echo "      docker compose up -d"
    exit 1
fi

echo ""
echo -e "${BLUE}[2/5]${NC} Fetching Prometheus metrics from ${METRICS_ENDPOINT}..."
METRICS_OUTPUT=$(curl -sk "${METRICS_ENDPOINT}")

if [ -z "$METRICS_OUTPUT" ]; then
    echo -e "${RED}✗${NC} Failed to fetch metrics"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Metrics endpoint responded"

echo ""
echo -e "${BLUE}[3/5]${NC} Validating expected metrics are present..."

EXPECTED_METRICS=(
    "vnf_broker_http_requests_total"
    "vnf_broker_request_latency_seconds"
    "vnf_broker_rate_limit_allowed_total"
    "vnf_broker_rate_limit_blocked_total"
    "vnf_broker_jwt_invalid_total"
    "vnf_broker_circuit_breaker_state"
)

MISSING_METRICS=()
for metric in "${EXPECTED_METRICS[@]}"; do
    if echo "$METRICS_OUTPUT" | grep -q "$metric"; then
        echo -e "  ${GREEN}[OK]${NC} $metric"
    else
        echo -e "  ${RED}✗${NC} $metric (MISSING)"
        MISSING_METRICS+=("$metric")
    fi
done

if [ ${#MISSING_METRICS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}ERROR:${NC} Missing metrics: ${MISSING_METRICS[*]}"
    exit 1
fi

echo ""
echo -e "${BLUE}[4/5]${NC} Sample metrics output:"
echo "----------------------------------------"
echo "$METRICS_OUTPUT" | head -50
echo "... (truncated, see full output with: curl -sk ${METRICS_ENDPOINT})"
echo "----------------------------------------"

echo ""
echo -e "${BLUE}[5/5]${NC} Prometheus scrape configuration example:"
cat <<EOF
scrape_configs:
  - job_name: 'vnf-broker'
    scheme: https
    metrics_path: /metrics.prom
    static_configs:
      - targets: ['localhost:8443']
    tls_config:
      insecure_skip_verify: true  # dev only
EOF

echo ""
echo -e "${GREEN}=========================================="
echo "[OK] All Prometheus metrics validated!"
echo "==========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Configure Prometheus to scrape ${METRICS_ENDPOINT}"
echo "  2. Create dashboards in Grafana"
echo "  3. Set up alerts (see METRICS.md for examples)"
echo ""
