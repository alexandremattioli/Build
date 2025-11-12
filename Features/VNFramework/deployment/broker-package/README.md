# VNF Broker Deployment Package

This package contains everything needed to deploy the VNF Broker on a Virtual Router.

## Package Contents

```
broker-package/
├── install_broker.sh          # Automated installation script
├── vnf_broker_redis.py        # Broker application with Redis
├── vnf_broker_private.pem     # RS256 private key (SECURE)
├── vnf_broker_public.pem      # RS256 public key (for CloudStack)
└── README.md                  # This file
```

## Quick Start

### 1. Copy Package to Virtual Router

```bash
scp -r broker-package/ root@<vr-ip>:/tmp/
ssh root@<vr-ip>
cd /tmp/broker-package
```

### 2. Run Installation

```bash
sudo ./install_broker.sh
```

With custom Redis:
```bash
sudo ./install_broker.sh --redis-host 192.168.1.100 --redis-port 6379
```

### 3. Verify Installation

```bash
# Check service status
systemctl status vnfbroker

# Test health endpoint
curl -k https://localhost:8443/health

# View logs
journalctl -u vnfbroker -f
```

## Configuration

### Environment Variables

Configuration is stored in `/etc/vnfbroker/broker.env`:

```bash
BROKER_HOST=0.0.0.0
BROKER_PORT=8443
REDIS_HOST=localhost
REDIS_PORT=6379
TLS_CERT_PATH=/etc/vnfbroker/tls/cert.pem
TLS_KEY_PATH=/etc/vnfbroker/tls/key.pem
JWT_ALGORITHM=RS256
JWT_PRIVATE_KEY=/etc/vnfbroker/tls/jwt_private.pem
LOG_FILE=/var/log/vnfbroker/broker.log
```

### Directory Structure

```
/opt/vnfbroker/
├── app/
│   └── broker.py              # Application code
├── venv/                      # Python virtual environment
└── logs/                      # Application logs

/etc/vnfbroker/
├── broker.env                 # Configuration
├── tls/
│   ├── cert.pem              # TLS certificate
│   ├── key.pem               # TLS private key
│   └── jwt_private.pem       # JWT signing key
└── dictionaries/              # VNF vendor dictionaries

/var/log/vnfbroker/
├── broker.log                 # Application log
├── access.log                 # HTTP access log
└── error.log                  # Error log
```

## CloudStack Integration

### 1. Copy Public Key to CloudStack

```bash
# On Virtual Router
cat /etc/vnfbroker/tls/../vnf_broker_public.pem

# Copy output and save to CloudStack server as:
# /etc/cloudstack/management/vnf_broker_public.pem
```

### 2. Configure CloudStack

Add to CloudStack global settings:

```sql
-- Set broker URL
UPDATE configuration 
SET value = 'https://<vr-ip>:8443'
WHERE name = 'vnf.broker.default.url';

-- Set JWT public key path
UPDATE configuration 
SET value = '/etc/cloudstack/management/vnf_broker_public.pem'
WHERE name = 'vnf.broker.jwt.publickey';
```

### 3. Test Integration

From CloudStack management server:

```bash
# Generate test JWT (use CloudStack's JWT generator)
TOKEN=$(java -cp cloudstack.jar org.apache.cloudstack.vnf.JwtGenerator)

# Test create firewall rule
curl -k -X POST https://<vr-ip>:8443/create-firewall-rule \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotency_key": "test-123",
    "source": {"cidr": "10.0.0.0/24"},
    "destination": {"cidr": "192.168.1.0/24"},
    "service": {"protocol": "TCP", "ports": [80, 443]},
    "action": "ACCEPT"
  }'
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl status vnfbroker

# View detailed logs
journalctl -u vnfbroker -n 100 --no-pager

# Check configuration
cat /etc/vnfbroker/broker.env

# Test Python syntax
/opt/vnfbroker/venv/bin/python /opt/vnfbroker/app/broker.py --help
```

### Redis Connection Issues

```bash
# Test Redis connectivity
redis-cli -h localhost -p 6379 ping

# Check Redis service
systemctl status redis-server

# View Redis logs
journalctl -u redis-server -n 50
```

### JWT Authentication Failures

```bash
# Verify private key exists
ls -la /etc/vnfbroker/tls/jwt_private.pem

# Check public key fingerprint
openssl rsa -pubin -in vnf_broker_public.pem -pubout -outform DER | sha256sum

# Ensure CloudStack has matching public key
```

### Health Check Fails

```bash
# Test locally with curl
curl -k -v https://localhost:8443/health

# Check if port is listening
netstat -tlnp | grep 8443

# Check firewall rules
iptables -L -n | grep 8443
```

## Security Considerations

### Private Key Security

**CRITICAL**: The `vnf_broker_private.pem` file contains the private key for JWT signing.

- [OK] **DO**: Store securely on broker host only
- [OK] **DO**: Set permissions to 600 (readable only by vnfbroker user)
- [OK] **DO**: Rotate every 90 days
- [X] **DON'T**: Commit to version control
- [X] **DON'T**: Copy to CloudStack server
- [X] **DON'T**: Share via email/chat

### TLS Certificate

The installation script generates a self-signed certificate for development.

**For Production:**
```bash
# Replace with CA-signed certificate
cp your-cert.pem /etc/vnfbroker/tls/cert.pem
cp your-key.pem /etc/vnfbroker/tls/key.pem
chown vnfbroker:vnfbroker /etc/vnfbroker/tls/*.pem
chmod 600 /etc/vnfbroker/tls/key.pem
systemctl restart vnfbroker
```

### Firewall Rules

```bash
# Allow broker port from CloudStack management network only
iptables -A INPUT -p tcp --dport 8443 -s <mgmt-network>/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 8443 -j DROP
```

## Monitoring

### Service Health

```bash
# Check service status
systemctl is-active vnfbroker

# Health endpoint
curl -k https://localhost:8443/health
# Expected: {"status": "healthy", "redis": "connected", "timestamp": "..."}
```

### Resource Usage

```bash
# CPU and memory
systemctl status vnfbroker | grep -E 'CPU|Memory'

# Detailed process info
ps aux | grep vnfbroker

# Log file size
du -h /var/log/vnfbroker/
```

### Redis Monitoring

```bash
# Redis info
redis-cli info stats

# Key count (idempotency keys)
redis-cli DBSIZE

# Monitor commands in real-time
redis-cli monitor
```

## Maintenance

### Log Rotation

Logs are automatically rotated. Manual rotation:

```bash
# Rotate logs
logrotate -f /etc/logrotate.d/vnfbroker

# Or use journalctl for systemd logs
journalctl --vacuum-time=7d
```

### Updating Broker

```bash
# Stop service
systemctl stop vnfbroker

# Backup current version
cp /opt/vnfbroker/app/broker.py /opt/vnfbroker/app/broker.py.backup

# Deploy new version
cp vnf_broker_redis.py /opt/vnfbroker/app/broker.py
chown vnfbroker:vnfbroker /opt/vnfbroker/app/broker.py

# Restart service
systemctl start vnfbroker
systemctl status vnfbroker
```

### Key Rotation (Every 90 Days)

```bash
# Generate new keypair
./generate_rs256_keys.sh

# Install new private key
cp vnf_broker_private.pem /etc/vnfbroker/tls/jwt_private.pem
chmod 600 /etc/vnfbroker/tls/jwt_private.pem
chown vnfbroker:vnfbroker /etc/vnfbroker/tls/jwt_private.pem

# Restart broker
systemctl restart vnfbroker

# Update CloudStack with new public key
# (Coordinate maintenance window - brief JWT validation failure expected)
```

## Performance Tuning

### Gunicorn Workers

Edit `/etc/systemd/system/vnfbroker.service`:

```ini
# Adjust workers based on CPU cores
ExecStart=/opt/vnfbroker/venv/bin/gunicorn \
    --workers 8 \          # Increase for more concurrent requests
    --timeout 120 \
    ...
```

### Redis Memory

Edit `/etc/redis/redis.conf`:

```conf
# Set max memory
maxmemory 256mb

# Set eviction policy
maxmemory-policy allkeys-lru
```

Restart Redis:
```bash
systemctl restart redis-server
```

## Support

- Documentation: /Builder2/Build/Features/VNFramework/
- Issues: https://github.com/alexandremattioli/Build/issues
- Logs: `journalctl -u vnfbroker -f`

## Version

- Broker Version: 1.0.0
- Redis Integration: Yes
- JWT Algorithm: RS256
- Build Date: 2025-11-07
