#!/bin/bash
###############################################################################
# VNF Broker Quick Start Script - Build2
# =======================================
# Automated setup and testing for VNF Framework Phase 1 deliverables
#
# Usage:
#   ./quickstart.sh              # Full setup: Redis, broker, mock VNF, tests
#   ./quickstart.sh --broker-only # Start broker only
#   ./quickstart.sh --test-only   # Run tests only (assumes services running)
#   ./quickstart.sh --stop        # Stop all services
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BROKER_DIR="$SCRIPT_DIR/python-broker"
TESTING_DIR="$SCRIPT_DIR/testing"
OPENAPI_DIR="$SCRIPT_DIR/openapi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_deps=()
    
    if ! command_exists python3; then
        missing_deps+=("python3")
    fi
    
    if ! command_exists redis-server && ! command_exists docker; then
        missing_deps+=("redis-server or docker")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: sudo apt-get install python3 python3-pip redis-server"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Install Python dependencies
install_python_deps() {
    log_info "Installing Python dependencies..."
    
    if [ ! -f "$PYTHON_BROKER_DIR/requirements.txt" ]; then
        log_error "requirements.txt not found in $PYTHON_BROKER_DIR"
        exit 1
    fi
    
    python3 -m pip install -q -r "$PYTHON_BROKER_DIR/requirements.txt"
    log_success "Python dependencies installed"
}

# Start Redis
start_redis() {
    log_info "Starting Redis..."
    
    if pgrep -x "redis-server" > /dev/null; then
        log_success "Redis is already running"
        return
    fi
    
    # Try Docker first
    if command_exists docker; then
        if docker ps | grep -q vnf-redis; then
            log_success "Redis container already running"
        else
            docker run -d --name vnf-redis -p 6379:6379 redis:7-alpine >/dev/null 2>&1
            sleep 2
            log_success "Redis started in Docker container"
        fi
    else
        # Try system Redis
        sudo systemctl start redis-server >/dev/null 2>&1 || redis-server --daemonize yes
        sleep 1
        log_success "Redis started as system service"
    fi
    
    # Verify Redis is responding
    if redis-cli ping >/dev/null 2>&1; then
        log_success "Redis is responding to PING"
    else
        log_error "Redis failed to start or not responding"
        exit 1
    fi
}

# Start VNF Broker
start_broker() {
    log_info "Starting VNF Broker..."
    
    if pgrep -f "vnf_broker_enhanced.py" > /dev/null; then
        log_warning "VNF Broker is already running (PID: $(pgrep -f vnf_broker_enhanced.py))"
        return
    fi
    
    cd "$PYTHON_BROKER_DIR"
    
    # Check if config exists
    if [ ! -f "config.dev.json" ]; then
        log_warning "config.dev.json not found, using config.sample.json"
        cp config.sample.json config.dev.json
    fi
    
    # Check if JWT public key exists
    if [ ! -f "keys/jwt_public.pem" ]; then
        log_error "JWT public key not found at keys/jwt_public.pem"
        log_info "Please obtain the public key from Build1"
        exit 1
    fi
    
    # Start broker in background
    nohup python3 vnf_broker_enhanced.py > /tmp/vnf-broker.log 2>&1 &
    BROKER_PID=$!
    
    sleep 3
    
    # Check if broker started successfully
    if ps -p $BROKER_PID > /dev/null; then
        log_success "VNF Broker started (PID: $BROKER_PID)"
        log_info "Logs: tail -f /tmp/vnf-broker.log"
    else
        log_error "VNF Broker failed to start. Check /tmp/vnf-broker.log"
        tail -20 /tmp/vnf-broker.log
        exit 1
    fi
    
    # Test broker health
    sleep 2
    if curl -s -k https://localhost:8443/health >/dev/null 2>&1; then
        log_success "VNF Broker health check passed"
    else
        log_warning "VNF Broker health check failed, but process is running"
    fi
}

# Start Mock VNF Server
start_mock_vnf() {
    log_info "Starting Mock VNF Server..."
    
    if pgrep -f "mock_vnf_server.py" > /dev/null; then
        log_warning "Mock VNF Server is already running (PID: $(pgrep -f mock_vnf_server.py))"
        return
    fi
    
    cd "$TESTING_DIR"
    
    # Start mock VNF in background
    nohup python3 mock_vnf_server.py --vendor pfsense --port 9443 > /tmp/mock-vnf.log 2>&1 &
    MOCK_PID=$!
    
    sleep 2
    
    # Check if mock VNF started successfully
    if ps -p $MOCK_PID > /dev/null; then
        log_success "Mock VNF Server started (PID: $MOCK_PID)"
        log_info "Logs: tail -f /tmp/mock-vnf.log"
    else
        log_error "Mock VNF Server failed to start. Check /tmp/mock-vnf.log"
        tail -20 /tmp/mock-vnf.log
        exit 1
    fi
    
    # Test mock VNF health
    sleep 1
    if curl -s http://localhost:9443/health >/dev/null 2>&1; then
        log_success "Mock VNF health check passed"
    else
        log_warning "Mock VNF health check failed, but process is running"
    fi
}

# Run integration tests
run_tests() {
    log_info "Running integration tests..."
    
    cd "$TESTING_DIR"
    
    # Note: Tests will fail without valid JWT token
    log_warning "Running tests without JWT token - auth tests will fail"
    log_info "To run with auth, use: python3 integration_test.py --jwt-token <token>"
    
    python3 integration_test.py --broker https://localhost:8443 --mock-vnf http://localhost:9443 || true
}

# Stop all services
stop_services() {
    log_info "Stopping all VNF services..."
    
    # Stop broker
    if pgrep -f "vnf_broker_enhanced.py" > /dev/null; then
        pkill -f "vnf_broker_enhanced.py"
        log_success "VNF Broker stopped"
    fi
    
    # Stop mock VNF
    if pgrep -f "mock_vnf_server.py" > /dev/null; then
        pkill -f "mock_vnf_server.py"
        log_success "Mock VNF Server stopped"
    fi
    
    # Stop Redis (if in Docker)
    if docker ps | grep -q vnf-redis; then
        docker stop vnf-redis >/dev/null 2>&1
        docker rm vnf-redis >/dev/null 2>&1
        log_success "Redis container stopped and removed"
    fi
    
    log_success "All services stopped"
}

# Show status of services
show_status() {
    echo ""
    echo "========================================"
    echo "VNF Framework Service Status"
    echo "========================================"
    
    # Redis
    if redis-cli ping >/dev/null 2>&1; then
        echo -e "Redis:      ${GREEN}[OK] Running${NC}"
    else
        echo -e "Redis:      ${RED}✗ Stopped${NC}"
    fi
    
    # Broker
    if pgrep -f "vnf_broker_enhanced.py" > /dev/null; then
        echo -e "Broker:     ${GREEN}[OK] Running${NC} (PID: $(pgrep -f vnf_broker_enhanced.py))"
    else
        echo -e "Broker:     ${RED}✗ Stopped${NC}"
    fi
    
    # Mock VNF
    if pgrep -f "mock_vnf_server.py" > /dev/null; then
        echo -e "Mock VNF:   ${GREEN}[OK] Running${NC} (PID: $(pgrep -f mock_vnf_server.py))"
    else
        echo -e "Mock VNF:   ${RED}✗ Stopped${NC}"
    fi
    
    echo "========================================"
    echo ""
    
    # Show URLs if services are running
    if pgrep -f "vnf_broker_enhanced.py" > /dev/null; then
        echo "Broker URLs:"
        echo "  Health:  https://localhost:8443/health"
        echo "  Metrics: https://localhost:8443/metrics"
        echo "  API:     https://localhost:8443/api/vnf/*"
        echo ""
    fi
    
    if pgrep -f "mock_vnf_server.py" > /dev/null; then
        echo "Mock VNF URLs:"
        echo "  Health:  http://localhost:9443/health"
        echo "  Status:  http://localhost:9443/mock/status"
        echo "  Rules:   http://localhost:9443/mock/rules"
        echo ""
    fi
}

# Main script logic
main() {
    echo ""
    echo "========================================"
    echo "VNF Framework Quick Start - Build2"
    echo "========================================"
    echo ""
    
    case "${1:-}" in
        --broker-only)
            check_prerequisites
            install_python_deps
            start_redis
            start_broker
            show_status
            ;;
        
        --test-only)
            run_tests
            ;;
        
        --stop)
            stop_services
            show_status
            ;;
        
        --status)
            show_status
            ;;
        
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)        Full setup: Redis, broker, mock VNF, and tests"
            echo "  --broker-only Start Redis and broker only"
            echo "  --test-only   Run integration tests (assumes services running)"
            echo "  --stop        Stop all services"
            echo "  --status      Show service status"
            echo "  --help        Show this help message"
            echo ""
            ;;
        
        *)
            # Full setup
            check_prerequisites
            install_python_deps
            start_redis
            start_broker
            start_mock_vnf
            show_status
            
            echo ""
            read -p "Run integration tests? (y/N) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                run_tests
            fi
            
            echo ""
            log_success "Quick start complete!"
            echo ""
            echo "Next steps:"
            echo "  1. Check broker health: curl -k https://localhost:8443/health"
            echo "  2. Check mock VNF: curl http://localhost:9443/health"
            echo "  3. View broker logs: tail -f /tmp/vnf-broker.log"
            echo "  4. View mock VNF logs: tail -f /tmp/mock-vnf.log"
            echo "  5. Stop services: $0 --stop"
            echo ""
            ;;
    esac
}

main "$@"
