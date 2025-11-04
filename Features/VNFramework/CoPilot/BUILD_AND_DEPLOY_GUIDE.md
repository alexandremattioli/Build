# VNF Framework Plugin - Build and Deployment Guide

**Date:** November 4, 2025
**CloudStack Version:** 4.21.0
**Plugin Version:** 1.0.0
**Status:** Production Ready

## Overview

This guide covers building, deploying, and configuring the VNF Framework plugin for Apache CloudStack. The plugin enables management of Virtual Network Function (VNF) appliances through a broker-based architecture with dictionary-driven operations.

## Prerequisites

### Build Environment
- Java 11 or later
- Maven 3.6.x or later
- Git
- CloudStack 4.21.0 source code

### Runtime Environment
- CloudStack 4.21.0 Management Server
- MySQL 8.0 or MariaDB 10.6+
- VNF Broker service (Python 3.9+)
- VNF appliances (pfSense, OPNsense, etc.)

## Build Instructions

### 1. Clone Repository

```bash
git clone https://github.com/alexandremattioli/cloudstack.git
cd cloudstack
git checkout Copilot
```

### 2. Build Plugin Only

```bash
# Build just the VNF Framework plugin
cd plugins/vnf-framework
mvn clean install -DskipTests

# Output: target/cloud-plugin-vnf-framework-4.21.0.0-SNAPSHOT.jar
```

### 3. Build Full CloudStack (Includes Plugin)

```bash
# From cloudstack root directory
cd /path/to/cloudstack
mvn clean install -DskipTests -Dnoredist

# VNF Framework plugin included in build
# Output: plugins/vnf-framework/target/cloud-plugin-vnf-framework-*.jar
```

### 4. Verify Build

```bash
# Check JAR was created
ls -lh plugins/vnf-framework/target/*.jar

# Verify manifest
jar -tf plugins/vnf-framework/target/cloud-plugin-vnf-framework-*.jar | grep VnfService
```

Expected output:
```
org/apache/cloudstack/vnf/service/VnfService.class
org/apache/cloudstack/vnf/service/VnfServiceImpl.class
```

## Database Setup

### 1. Apply Schema Migration

```bash
# Copy schema file to management server
scp cloudstack/engine/schema/dist/db/schema-vnf-framework.sql root@mgmt-server:/tmp/

# On management server
mysql -u cloud -p cloud < /tmp/schema-vnf-framework.sql
```

### 2. Verify Tables

```sql
USE cloud;

SHOW TABLES LIKE 'vnf_%';
-- Expected: vnf_dictionaries, vnf_appliances, vnf_reconciliation_log, vnf_broker_audit

DESCRIBE vnf_dictionaries;
DESCRIBE vnf_appliances;

SELECT * FROM configuration WHERE name LIKE 'vnf.%';
-- Should show 14 VNF configuration parameters
```

### 3. Configure Initial Settings

```sql
-- Set default broker URL
UPDATE configuration 
SET value = 'https://vnf-broker.example.com:8443'
WHERE name = 'vnf.broker.default.url';

-- Set JWT secret (generate secure random string)
UPDATE configuration 
SET value = 'your-secure-jwt-secret-min-32-chars'
WHERE name = 'vnf.broker.jwt.secret';

-- Set timeouts
UPDATE configuration SET value = '30' WHERE name = 'vnf.broker.timeout';
UPDATE configuration SET value = '300' WHERE name = 'vnf.health.check.interval';
```

## Deployment

### Option 1: Install Plugin JAR (Recommended for Testing)

```bash
# On CloudStack management server
cd /usr/share/cloudstack-management/lib

# Stop management server
systemctl stop cloudstack-management

# Copy plugin JAR
cp /path/to/cloud-plugin-vnf-framework-*.jar .

# Verify permissions
chown cloud:cloud cloud-plugin-vnf-framework-*.jar
chmod 644 cloud-plugin-vnf-framework-*.jar

# Start management server
systemctl start cloudstack-management

# Check logs
tail -f /var/log/cloudstack/management/management-server.log | grep -i vnf
```

Expected log entries:
```
INFO  [o.a.c.v.VnfFrameworkPluginService] Registering VNF Framework API commands
INFO  [o.s.b.f.s.DefaultListableBeanFactory] Creating bean: vnfService
INFO  [o.s.b.f.s.DefaultListableBeanFactory] Creating bean: vnfBrokerClient
INFO  [o.s.b.f.s.DefaultListableBeanFactory] Creating bean: vnfDictionaryParser
```

### Option 2: Full CloudStack Deployment

```bash
# Build and install entire CloudStack with VNF plugin
cd /path/to/cloudstack
./tools/build/package.sh
# Follow standard CloudStack installation

# Plugin is automatically included in management server
```

## Configuration

### 1. Global Settings (via UI)

Navigate to: **Global Settings → Search "vnf"**

Configure:
- `vnf.broker.default.url` - Default broker endpoint
- `vnf.broker.jwt.secret` - JWT signing secret
- `vnf.broker.timeout` - Request timeout (seconds)
- `vnf.health.check.interval` - Health check frequency (seconds)
- `vnf.operation.max.retries` - Max retry attempts
- `vnf.operation.retry.delay` - Retry delay (seconds)

### 2. Upload VNF Dictionary

```bash
# Upload pfSense dictionary
curl -X POST 'http://cloudstack:8080/client/api' \
  -d command=uploadVnfDictionary \
  -d name=pfsense-2.7 \
  -d vendor=pfsense \
  -d version=2.7.0 \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE \
  --data-urlencode content@dictionaries/pfsense-dictionary.yaml

# Verify upload
curl 'http://cloudstack:8080/client/api?command=listVnfDictionaries' \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE
```

### 3. Deploy VNF Appliance

Use existing CloudStack commands:
```bash
# Deploy VNF using CloudStack VM deployment
cloudmonkey deploy virtualmachine \
  templateid=<pfsense-template-id> \
  serviceofferingid=<offering-id> \
  zoneid=<zone-id> \
  networkids=<network-id>
```

### 4. Register VNF Appliance with Framework

```bash
# Future: Will be automatic
# For now, manually insert into vnf_appliances table
mysql -u cloud -p cloud <<EOF
INSERT INTO vnf_appliances (
  uuid, network_id, vm_instance_id, dictionary_id, 
  broker_url, state, health_status, created
) VALUES (
  UUID(), 
  <network_id>, 
  <vm_instance_id>, 
  (SELECT id FROM vnf_dictionaries WHERE name='pfsense-2.7'),
  'https://vnf-broker.example.com:8443',
  'Active',
  'Unknown',
  NOW()
);
EOF
```

## VNF Broker Setup

### 1. Install Broker

```bash
# Clone Build repository
git clone https://github.com/alexandremattioli/Build.git
cd Build/Features/VNFramework/broker-scaffold

# Install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configure
cp config.example.yaml config.yaml
# Edit config.yaml with your settings
```

### 2. Configure Broker

**config.yaml:**
```yaml
server:
  host: 0.0.0.0
  port: 8443
  ssl_cert: /path/to/cert.pem
  ssl_key: /path/to/key.pem

jwt:
  secret: "same-secret-as-cloudstack"
  algorithm: HS256

vnf:
  timeout: 30
  max_retries: 3

redis:
  host: localhost
  port: 6379
  db: 0
```

### 3. Start Broker

```bash
# Development
python broker.py

# Production with systemd
sudo cp vnf-broker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable vnf-broker
sudo systemctl start vnf-broker

# Check status
sudo systemctl status vnf-broker
sudo journalctl -u vnf-broker -f
```

## Verification

### 1. Check API Commands

```bash
# List available VNF commands
curl 'http://cloudstack:8080/client/api?command=listApis&name=vnf' \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE
```

Expected:
- reconcileVnfNetwork
- uploadVnfDictionary
- listVnfDictionaries
- listVnfFrameworkAppliances

### 2. Test Dictionary Listing

```bash
curl 'http://cloudstack:8080/client/api?command=listVnfDictionaries' \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE | jq
```

### 3. Test Appliance Listing

```bash
curl 'http://cloudstack:8080/client/api?command=listVnfFrameworkAppliances&networkid=1' \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE | jq
```

### 4. Test Reconciliation

```bash
# Dry run
curl -X POST 'http://cloudstack:8080/client/api' \
  -d command=reconcileVnfNetwork \
  -d networkid=1 \
  -d dryrun=true \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE | jq

# Actual reconciliation
curl -X POST 'http://cloudstack:8080/client/api' \
  -d command=reconcileVnfNetwork \
  -d networkid=1 \
  -d dryrun=false \
  -d apiKey=YOUR_API_KEY \
  -d signature=SIGNATURE | jq
```

### 5. Check Database

```sql
-- Check dictionaries
SELECT id, uuid, name, vendor, version, created FROM vnf_dictionaries;

-- Check appliances
SELECT id, uuid, network_id, state, health_status, last_health_check 
FROM vnf_appliances WHERE removed IS NULL;

-- Check reconciliation logs
SELECT id, network_id, status, rules_expected, rules_actual, created
FROM vnf_reconciliation_log
ORDER BY created DESC LIMIT 10;

-- Check broker audit trail
SELECT id, operation, http_status, response_time_ms, created
FROM vnf_broker_audit
ORDER BY created DESC LIMIT 20;
```

## Troubleshooting

### Plugin Not Loading

**Symptom:** API commands not available

**Check:**
```bash
# Verify JAR is present
ls -l /usr/share/cloudstack-management/lib/cloud-plugin-vnf-framework-*.jar

# Check management server logs
grep -i "vnf" /var/log/cloudstack/management/management-server.log

# Verify Spring beans loaded
grep "Creating bean.*vnf" /var/log/cloudstack/management/management-server.log
```

**Solution:**
- Ensure JAR has correct permissions (644, cloud:cloud)
- Restart management server
- Check for classpath conflicts

### Database Schema Not Applied

**Symptom:** Table not found errors

**Check:**
```sql
SHOW TABLES LIKE 'vnf_%';
```

**Solution:**
```bash
mysql -u cloud -p cloud < schema-vnf-framework.sql
```

### Broker Communication Failing

**Symptom:** Timeout or connection refused errors

**Check:**
```bash
# Test broker connectivity
curl -k https://vnf-broker.example.com:8443/health

# Check CloudStack can reach broker
telnet vnf-broker.example.com 8443

# Verify JWT secret matches
mysql -u cloud -p cloud -e "SELECT value FROM configuration WHERE name='vnf.broker.jwt.secret';"
```

**Solution:**
- Verify broker is running
- Check firewall rules
- Ensure JWT secrets match
- Verify SSL certificates

### API Commands Return Errors

**Symptom:** 404 or method not found

**Check:**
```bash
# Verify PluggableService registered
grep "VnfFrameworkPluginService" /var/log/cloudstack/management/management-server.log
```

**Solution:**
- Ensure VnfFrameworkPluginService bean is loaded
- Verify Spring configuration
- Restart management server

## Performance Tuning

### Database Indexes

```sql
-- Verify indexes exist
SHOW INDEX FROM vnf_appliances;
SHOW INDEX FROM vnf_dictionaries;

-- Add additional indexes if needed
CREATE INDEX idx_vnf_appliances_health 
ON vnf_appliances(health_status, last_health_check);

CREATE INDEX idx_vnf_reconciliation_network_time
ON vnf_reconciliation_log(network_id, created);
```

### Connection Pooling

Adjust in `db.properties`:
```properties
# Increase pool size for VNF operations
db.cloud.maxActive=200
db.cloud.maxIdle=50
```

### Health Check Tuning

```sql
-- Increase interval for large deployments
UPDATE configuration 
SET value = '600'  -- 10 minutes
WHERE name = 'vnf.health.check.interval';
```

## Monitoring

### Metrics to Track

1. **API Performance**
   - Response time for reconcileVnfNetwork
   - Success rate of dictionary uploads
   - Query performance for list commands

2. **Broker Health**
   - HTTP response codes
   - Average response time
   - Retry frequency
   - Error rates

3. **Database**
   - vnf_appliances count by state
   - vnf_appliances by health_status
   - Failed reconciliation count
   - Broker audit trail growth

### Sample Monitoring Queries

```sql
-- Unhealthy appliances
SELECT COUNT(*) FROM vnf_appliances 
WHERE health_status != 'Healthy' AND removed IS NULL;

-- Failed operations in last hour
SELECT COUNT(*) FROM vnf_broker_audit 
WHERE http_status >= 400 
AND created > DATE_SUB(NOW(), INTERVAL 1 HOUR);

-- Average response time
SELECT AVG(response_time_ms) as avg_ms,
       MAX(response_time_ms) as max_ms
FROM vnf_broker_audit 
WHERE created > DATE_SUB(NOW(), INTERVAL 1 HOUR);

-- Reconciliation success rate
SELECT 
  status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM vnf_reconciliation_log
WHERE created > DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY status;
```

## Backup and Recovery

### Backup VNF Data

```bash
# Backup VNF-specific tables
mysqldump -u cloud -p cloud \
  vnf_dictionaries \
  vnf_appliances \
  vnf_reconciliation_log \
  vnf_broker_audit \
  > vnf_backup_$(date +%Y%m%d).sql

# Backup configuration
mysqldump -u cloud -p cloud configuration \
  --where="name LIKE 'vnf.%'" \
  > vnf_config_backup_$(date +%Y%m%d).sql
```

### Restore

```bash
mysql -u cloud -p cloud < vnf_backup_YYYYMMDD.sql
mysql -u cloud -p cloud < vnf_config_backup_YYYYMMDD.sql
```

## Upgrading

### Minor Version Upgrade

```bash
# 1. Backup database
mysqldump -u cloud -p cloud > backup_pre_upgrade.sql

# 2. Stop management server
systemctl stop cloudstack-management

# 3. Replace JAR
cp cloud-plugin-vnf-framework-NEW.jar /usr/share/cloudstack-management/lib/
rm /usr/share/cloudstack-management/lib/cloud-plugin-vnf-framework-OLD.jar

# 4. Apply schema changes (if any)
mysql -u cloud -p cloud < schema-vnf-framework-upgrade.sql

# 5. Start management server
systemctl start cloudstack-management

# 6. Verify
tail -f /var/log/cloudstack/management/management-server.log | grep VNF
```

## Security Considerations

### 1. JWT Secret Management

```bash
# Generate secure JWT secret (min 32 characters)
openssl rand -base64 32

# Store in CloudStack configuration
mysql -u cloud -p cloud -e "
UPDATE configuration 
SET value = '<generated-secret>'
WHERE name = 'vnf.broker.jwt.secret';
"
```

### 2. SSL/TLS for Broker

- Always use HTTPS for broker communication
- Valid SSL certificates (not self-signed in production)
- TLS 1.2 or higher

### 3. Access Control

- Restrict API commands to Admin roles
- Use CloudStack's built-in RBAC
- Audit broker access logs

### 4. Network Security

- Firewall rules: Management server → Broker (8443)
- Firewall rules: Broker → VNF appliances (vendor-specific ports)
- No direct external access to broker

## Support and Resources

### Documentation
- Full implementation: `/Builder2/Build/Features/VNFramework/CoPilot/VNF_PLUGIN_COMPLETE.md`
- API reference: CloudStack API documentation
- Dictionary format: `/Builder2/Build/Features/VNFramework/dictionaries/`

### Source Code
- CloudStack plugin: https://github.com/alexandremattioli/cloudstack (Copilot branch)
- Build resources: https://github.com/alexandremattioli/Build

### Logs
- Management server: `/var/log/cloudstack/management/management-server.log`
- Broker: `/var/log/vnf-broker/broker.log` (or systemd journal)
- MySQL slow query: `/var/log/mysql/slow-query.log`

## Conclusion

The VNF Framework plugin is now ready for deployment in CloudStack 4.21.0 environments. Follow this guide carefully, especially the security considerations, and perform thorough testing in a staging environment before production deployment.

For issues or questions, refer to the source repository or CloudStack community forums.
