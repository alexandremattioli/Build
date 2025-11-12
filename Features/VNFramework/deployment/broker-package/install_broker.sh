#!/bin/bash
# VNF Broker Installation Script for Virtual Router
# Usage: sudo ./install_broker.sh [--redis-host localhost] [--broker-port 8443]

set -e

# Default configuration
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
BROKER_PORT="${BROKER_PORT:-8443}"
BROKER_HOST="${BROKER_HOST:-0.0.0.0}"
INSTALL_DIR="/opt/vnfbroker"
CONFIG_DIR="/etc/vnfbroker"
LOG_DIR="/var/log/vnfbroker"
BROKER_USER="vnfbroker"

echo "=== VNF Broker Installation ==="
echo ""
echo "Configuration:"
echo "  Install directory: $INSTALL_DIR"
echo "  Config directory:  $CONFIG_DIR"
echo "  Log directory:     $LOG_DIR"
echo "  Redis host:        $REDIS_HOST:$REDIS_PORT"
echo "  Broker port:       $BROKER_PORT"
echo ""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --redis-host)
            REDIS_HOST="$2"
            shift 2
            ;;
        --redis-port)
            REDIS_PORT="$2"
            shift 2
            ;;
        --broker-port)
            BROKER_PORT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root"
   exit 1
fi

echo "Step 1: Installing system dependencies..."
apt-get update -qq
apt-get install -y python3.11 python3.11-venv redis-server openssl curl

echo "Step 2: Creating broker user and directories..."
if ! id -u $BROKER_USER > /dev/null 2>&1; then
    useradd -r -s /bin/bash -d $INSTALL_DIR $BROKER_USER
fi

mkdir -p $INSTALL_DIR/{app,venv,logs}
mkdir -p $CONFIG_DIR/{tls,dictionaries}
mkdir -p $LOG_DIR
chown -R $BROKER_USER:$BROKER_USER $INSTALL_DIR $CONFIG_DIR $LOG_DIR

echo "Step 3: Installing Python dependencies..."
sudo -u $BROKER_USER python3.11 -m venv $INSTALL_DIR/venv
$INSTALL_DIR/venv/bin/pip install --upgrade pip
$INSTALL_DIR/venv/bin/pip install flask redis pyjwt cryptography gunicorn

echo "Step 4: Deploying broker application..."
cp vnf_broker_redis.py $INSTALL_DIR/app/broker.py
chown $BROKER_USER:$BROKER_USER $INSTALL_DIR/app/broker.py
chmod 755 $INSTALL_DIR/app/broker.py

echo "Step 5: Configuring Redis..."
systemctl enable redis-server
systemctl start redis-server

# Test Redis connectivity
if ! redis-cli -h $REDIS_HOST -p $REDIS_PORT ping > /dev/null 2>&1; then
    echo "WARNING: Cannot connect to Redis at $REDIS_HOST:$REDIS_PORT"
    echo "Please ensure Redis is running and accessible"
fi

echo "Step 6: Generating self-signed TLS certificate..."
if [ ! -f "$CONFIG_DIR/tls/cert.pem" ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout $CONFIG_DIR/tls/key.pem \
        -out $CONFIG_DIR/tls/cert.pem \
        -subj "/CN=$(hostname)/O=VNF Broker/C=US" \
        2>/dev/null
    chmod 600 $CONFIG_DIR/tls/key.pem
    chmod 644 $CONFIG_DIR/tls/cert.pem
    chown -R $BROKER_USER:$BROKER_USER $CONFIG_DIR/tls
    echo "[OK] Self-signed certificate generated"
else
    echo "[OK] TLS certificate already exists"
fi

echo "Step 7: Creating configuration file..."
cat > $CONFIG_DIR/broker.env << ENVEOF
# VNF Broker Configuration
BROKER_HOST=$BROKER_HOST
BROKER_PORT=$BROKER_PORT
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
TLS_CERT_PATH=$CONFIG_DIR/tls/cert.pem
TLS_KEY_PATH=$CONFIG_DIR/tls/key.pem
LOG_FILE=$LOG_DIR/broker.log
ENVEOF

# Check if RS256 keys exist
if [ -f "vnf_broker_private.pem" ]; then
    echo "Step 8: Installing RS256 private key..."
    cp vnf_broker_private.pem $CONFIG_DIR/tls/jwt_private.pem
    chmod 600 $CONFIG_DIR/tls/jwt_private.pem
    chown $BROKER_USER:$BROKER_USER $CONFIG_DIR/tls/jwt_private.pem
    echo "JWT_ALGORITHM=RS256" >> $CONFIG_DIR/broker.env
    echo "JWT_PRIVATE_KEY=$CONFIG_DIR/tls/jwt_private.pem" >> $CONFIG_DIR/broker.env
    echo "[OK] RS256 JWT configured"
else
    echo "Step 8: Configuring HS256 JWT (RS256 key not found)..."
    JWT_SECRET=$(openssl rand -base64 32)
    echo "JWT_ALGORITHM=HS256" >> $CONFIG_DIR/broker.env
    echo "JWT_SECRET=$JWT_SECRET" >> $CONFIG_DIR/broker.env
    echo "WARNING: Using HS256. For production, use RS256 with generate_rs256_keys.sh"
fi

chown $BROKER_USER:$BROKER_USER $CONFIG_DIR/broker.env
chmod 600 $CONFIG_DIR/broker.env

echo "Step 9: Creating systemd service..."
cat > /etc/systemd/system/vnfbroker.service << 'SERVICEEOF'
[Unit]
Description=VNF Broker Service
Documentation=https://github.com/alexandremattioli/Build
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=vnfbroker
Group=vnfbroker
WorkingDirectory=/opt/vnfbroker/app
EnvironmentFile=/etc/vnfbroker/broker.env

ExecStart=/opt/vnfbroker/venv/bin/gunicorn \
    --bind ${BROKER_HOST}:${BROKER_PORT} \
    --workers 4 \
    --timeout 120 \
    --certfile ${TLS_CERT_PATH} \
    --keyfile ${TLS_KEY_PATH} \
    --access-logfile /var/log/vnfbroker/access.log \
    --error-logfile /var/log/vnfbroker/error.log \
    broker:app

Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/vnfbroker
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true
LimitNOFILE=65536
LimitNPROC=512

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload

echo "Step 10: Starting VNF Broker service..."
systemctl enable vnfbroker
systemctl restart vnfbroker

echo ""
echo "Waiting for service to start..."
sleep 3

if systemctl is-active --quiet vnfbroker; then
    echo "[OK] VNF Broker service started successfully"
    
    # Test health endpoint
    if curl -k -f https://localhost:$BROKER_PORT/health > /dev/null 2>&1; then
        echo "[OK] Health check passed"
    else
        echo "WARNING: Health check failed"
    fi
else
    echo "ERROR: Service failed to start"
    echo "Check logs: journalctl -u vnfbroker -n 50"
    exit 1
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Service status: systemctl status vnfbroker"
echo "View logs:      journalctl -u vnfbroker -f"
echo "Test health:    curl -k https://localhost:$BROKER_PORT/health"
echo ""
echo "Next steps:"
echo "  1. Copy vnf_broker_public.pem to CloudStack management server"
echo "  2. Configure CloudStack with broker URL: https://$(hostname):$BROKER_PORT"
echo "  3. Upload VNF dictionaries to $CONFIG_DIR/dictionaries/"
echo "  4. Test with: curl -k https://localhost:$BROKER_PORT/health"
echo ""
