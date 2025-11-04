# VNF Broker Deployment with Ansible

Automated deployment of VNF Broker service to CloudStack Virtual Routers using Ansible.

## Prerequisites

- Ansible 2.9+ on deployment machine
- Root SSH access to Virtual Routers
- Python 3.11 available on target hosts (will be installed if missing)
- JWT secret for broker authentication

## Directory Structure

```
deployment/ansible/
├── deploy_broker.yml          # Main deployment playbook
├── verify_deployment.yml      # Verification playbook
├── inventory.ini              # Host inventory
├── broker_config.env.j2       # Environment configuration template
├── vnfbroker.service.j2       # Systemd service template
└── README.md                  # This file
```

## Quick Start

### 1. Configure Inventory

Edit `inventory.ini` with your Virtual Router IP addresses:

```ini
[virtual_routers]
vr-1 ansible_host=192.168.1.10 ansible_user=root
vr-2 ansible_host=192.168.1.11 ansible_user=root
```

### 2. Set JWT Secret

Generate a secure JWT secret:

```bash
export BROKER_JWT_SECRET=$(openssl rand -base64 32)
```

Update `inventory.ini` with the secret:

```ini
[virtual_routers:vars]
jwt_secret=your_generated_secret_here
```

### 3. Deploy Broker

```bash
ansible-playbook -i inventory.ini deploy_broker.yml
```

### 4. Verify Deployment

```bash
# Generate JWT token for testing
export BROKER_JWT_TOKEN=$(python3 -c "
import jwt
import datetime
token = jwt.encode({
    'sub': 'admin',
    'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=1)
}, '$BROKER_JWT_SECRET', algorithm='HS256')
print(token)
")

# Run verification
ansible-playbook -i inventory.ini verify_deployment.yml
```

## Configuration Variables

Edit in `inventory.ini` under `[virtual_routers:vars]`:

| Variable | Default | Description |
|----------|---------|-------------|
| `broker_port` | 8443 | HTTPS port for broker service |
| `redis_host` | localhost | Redis server host |
| `redis_port` | 6379 | Redis server port |
| `jwt_secret` | (required) | JWT signing secret |
| `broker_home` | /opt/vnfbroker | Broker installation directory |

## Deployment Tasks

The playbook performs the following:

1. **System Setup**
   - Creates `vnfbroker` system user
   - Installs Python 3.11, Redis, Nginx
   - Creates directory structure

2. **Application Deployment**
   - Copies broker application files
   - Installs Python dependencies in virtualenv
   - Deploys VNF dictionaries

3. **TLS Configuration**
   - Generates self-signed certificate (or deploys provided cert)
   - Sets secure permissions

4. **Redis Configuration**
   - Configures Redis for localhost binding
   - Sets memory limits and eviction policy

5. **Service Setup**
   - Creates systemd service with security hardening
   - Enables and starts VNF Broker service
   - Validates service health

## Security Hardening

The systemd service includes:

- `NoNewPrivileges=true` - Prevents privilege escalation
- `PrivateTmp=true` - Isolated /tmp directory
- `ProtectSystem=strict` - Read-only system directories
- `ProtectHome=true` - Restricted home directory access
- Resource limits (512M memory, 200% CPU)

## Manual Deployment Steps

If you prefer manual deployment:

```bash
# On Virtual Router
sudo su -

# Create user and directories
useradd -r -s /bin/bash vnfbroker
mkdir -p /opt/vnfbroker/{app,dictionaries,tls,logs}
mkdir -p /etc/vnfbroker/{dictionaries,tls}

# Install dependencies
apt install python3.11 python3.11-venv redis-server -y

# Deploy application
cd /opt/vnfbroker/app
python3.11 -m venv ../venv
../venv/bin/pip install -r requirements.txt

# Generate TLS certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/vnfbroker/tls/key.pem \
  -out /etc/vnfbroker/tls/cert.pem \
  -subj "/CN=$(hostname)"

# Configure and start service
cp vnfbroker.service /etc/systemd/system/
cp broker_config.env /etc/vnfbroker/broker.env
systemctl daemon-reload
systemctl enable --now vnfbroker
```

## Troubleshooting

### Service won't start

```bash
# Check service status
systemctl status vnfbroker

# View logs
journalctl -u vnfbroker -f

# Check application logs
tail -f /opt/vnfbroker/logs/broker.log
```

### Health check fails

```bash
# Test locally
curl -k https://localhost:8443/health

# Check if port is listening
netstat -tlnp | grep 8443

# Verify Redis connectivity
redis-cli ping
```

### Permission errors

```bash
# Fix ownership
chown -R vnfbroker:vnfbroker /opt/vnfbroker /etc/vnfbroker

# Fix TLS permissions
chmod 600 /etc/vnfbroker/tls/*.pem
```

### Dictionary not found

```bash
# List deployed dictionaries
ls -la /etc/vnfbroker/dictionaries/

# Verify dictionary syntax
python3 -c "import yaml; yaml.safe_load(open('/etc/vnfbroker/dictionaries/pfsense_2.7.yaml'))"
```

## Updating Broker

To update an existing deployment:

```bash
# Stop service
ansible virtual_routers -i inventory.ini -m systemd -a "name=vnfbroker state=stopped" -b

# Deploy new version
ansible-playbook -i inventory.ini deploy_broker.yml

# Service will restart automatically
```

## Rollback

To rollback to previous version:

```bash
# Restore backup (if created before deployment)
ansible virtual_routers -i inventory.ini -m shell -a \
  "cp /opt/vnfbroker/app.backup/* /opt/vnfbroker/app/" -b

# Restart service
ansible virtual_routers -i inventory.ini -m systemd -a \
  "name=vnfbroker state=restarted" -b
```

## Production Considerations

### High Availability

For production HA setup:

1. Deploy Redis in cluster mode or use managed Redis service
2. Use shared TLS certificates across all VRs
3. Configure external load balancer for broker endpoints
4. Set up centralized logging (ELK stack, Splunk)

### Monitoring

Add monitoring for:

- Service uptime (`systemctl status vnfbroker`)
- Health endpoint (`/health`)
- Redis connectivity
- Disk space usage
- Memory usage
- TLS certificate expiry

### Backup

Backup the following regularly:

- `/etc/vnfbroker/` - Configuration files
- `/opt/vnfbroker/dictionaries/` - Custom dictionaries
- `/etc/vnfbroker/tls/` - TLS certificates
- Redis data (if using persistence)

## Integration with CloudStack

Configure CloudStack Management Server to use deployed brokers:

```properties
# In /etc/cloudstack/management/management.properties
vnf.broker.url=https://<VR_IP>:8443
vnf.broker.jwt.secret=<same_as_broker_jwt_secret>
vnf.broker.timeout=30
vnf.broker.retry.max=3
```

Restart CloudStack Management Server:

```bash
systemctl restart cloudstack-management
```

## Support

For issues or questions:

- Check logs: `/opt/vnfbroker/logs/broker.log`
- Run verification: `ansible-playbook -i inventory.ini verify_deployment.yml`
- Review implementation log: `/root/Build/Features/VNFramework/IMPLEMENTATION_LOG.md`
