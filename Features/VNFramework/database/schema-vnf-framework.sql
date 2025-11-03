-- =====================================================
-- VNF Framework Database Schema for CloudStack 4.21.7
-- =====================================================
-- This migration adds support for Virtual Network Function (VNF) integration

-- =====================================================
-- 1. VNF Dictionary Storage
-- =====================================================
-- Stores YAML dictionaries that define how to communicate with VNF appliances
CREATE TABLE IF NOT EXISTS `vnf_dictionaries` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT 'ID of the dictionary',
  `uuid` varchar(40) UNIQUE COMMENT 'UUID of the dictionary',
  `template_id` bigint unsigned DEFAULT NULL COMMENT 'Template ID this dictionary is associated with',
  `network_id` bigint unsigned DEFAULT NULL COMMENT 'Network ID for override dictionaries (mutually exclusive with template_id)',
  `name` varchar(255) NOT NULL COMMENT 'Human-readable name for the dictionary',
  `yaml_content` MEDIUMTEXT NOT NULL COMMENT 'The YAML dictionary content',
  `schema_version` varchar(10) NOT NULL DEFAULT '1.0' COMMENT 'Dictionary schema version',
  `vendor` varchar(100) COMMENT 'Vendor name (extracted from YAML)',
  `product` varchar(100) COMMENT 'Product name (extracted from YAML)',
  `created` datetime NOT NULL COMMENT 'Date created',
  `updated` datetime COMMENT 'Date last updated',
  `removed` datetime COMMENT 'Date removed (soft delete)',
  PRIMARY KEY (`id`),
  KEY `fk_vnf_dictionaries_template_id` (`template_id`),
  KEY `fk_vnf_dictionaries_network_id` (`network_id`),
  CONSTRAINT `fk_vnf_dictionaries_template_id` FOREIGN KEY (`template_id`) REFERENCES `vm_template` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_vnf_dictionaries_network_id` FOREIGN KEY (`network_id`) REFERENCES `networks` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_vnf_dict_association` CHECK (
    (template_id IS NOT NULL AND network_id IS NULL) OR 
    (template_id IS NULL AND network_id IS NOT NULL)
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- =====================================================
-- 2. VNF Appliance Tracking
-- =====================================================
-- Tracks VNF appliance VMs and their association with networks
CREATE TABLE IF NOT EXISTS `vnf_appliances` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT 'ID of the VNF appliance',
  `uuid` varchar(40) UNIQUE COMMENT 'UUID of the VNF appliance',
  `vm_instance_id` bigint unsigned NOT NULL COMMENT 'VM instance ID of the VNF appliance',
  `network_id` bigint unsigned NOT NULL COMMENT 'Network this VNF serves',
  `template_id` bigint unsigned NOT NULL COMMENT 'VNF template used',
  `dictionary_id` bigint unsigned COMMENT 'Dictionary currently in use',
  `management_ip` varchar(40) COMMENT 'Management IP address of VNF',
  `guest_ip` varchar(40) COMMENT 'Guest network IP (typically the gateway IP)',
  `public_ip` varchar(40) COMMENT 'Public IP address if applicable',
  `broker_vm_id` bigint unsigned COMMENT 'Virtual Router acting as broker',
  `state` varchar(32) NOT NULL DEFAULT 'Deploying' COMMENT 'State: Deploying, Running, Stopped, Error, Destroyed',
  `last_contact` datetime COMMENT 'Last successful communication with VNF',
  `health_status` varchar(32) DEFAULT 'Unknown' COMMENT 'Health: Healthy, Unhealthy, Unknown',
  `created` datetime NOT NULL COMMENT 'Date created',
  `removed` datetime COMMENT 'Date removed',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_vnf_appliance_network` (`network_id`),
  KEY `fk_vnf_appliances_vm_id` (`vm_instance_id`),
  KEY `fk_vnf_appliances_template_id` (`template_id`),
  KEY `fk_vnf_appliances_dict_id` (`dictionary_id`),
  KEY `fk_vnf_appliances_broker_id` (`broker_vm_id`),
  CONSTRAINT `fk_vnf_appliances_vm_id` FOREIGN KEY (`vm_instance_id`) REFERENCES `vm_instance` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_vnf_appliances_template_id` FOREIGN KEY (`template_id`) REFERENCES `vm_template` (`id`),
  CONSTRAINT `fk_vnf_appliances_dict_id` FOREIGN KEY (`dictionary_id`) REFERENCES `vnf_dictionaries` (`id`),
  CONSTRAINT `fk_vnf_appliances_broker_id` FOREIGN KEY (`broker_vm_id`) REFERENCES `vm_instance` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- =====================================================
-- 3. External ID Mapping for Rules
-- =====================================================
-- Maps CloudStack rule IDs to vendor-specific IDs returned by VNF devices
-- This is critical for delete operations and reconciliation

-- Extend firewall_rules table
ALTER TABLE `firewall_rules` 
ADD COLUMN `external_id` varchar(255) COMMENT 'Vendor-specific rule ID on VNF device',
ADD COLUMN `external_metadata` TEXT COMMENT 'Additional vendor-specific metadata (JSON)';

-- Extend port_forwarding_rules table
ALTER TABLE `port_forwarding_rules`
ADD COLUMN `external_id` varchar(255) COMMENT 'Vendor-specific rule ID on VNF device',
ADD COLUMN `external_metadata` TEXT COMMENT 'Additional vendor-specific metadata (JSON)';

-- Extend load_balancing_rules table (if VNF supports LB)
ALTER TABLE `load_balancing_rules`
ADD COLUMN `external_id` varchar(255) COMMENT 'Vendor-specific rule ID on VNF device',
ADD COLUMN `external_metadata` TEXT COMMENT 'Additional vendor-specific metadata (JSON)';

-- =====================================================
-- 4. Reconciliation History
-- =====================================================
-- Tracks reconciliation runs and detected drift
CREATE TABLE IF NOT EXISTS `vnf_reconciliation_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(40) UNIQUE,
  `network_id` bigint unsigned NOT NULL COMMENT 'Network reconciled',
  `vnf_appliance_id` bigint unsigned COMMENT 'VNF appliance',
  `started` datetime NOT NULL COMMENT 'When reconciliation started',
  `completed` datetime COMMENT 'When reconciliation completed',
  `status` varchar(32) NOT NULL COMMENT 'Status: Running, Success, Failed, PartialSuccess',
  `rules_checked` int DEFAULT 0 COMMENT 'Number of rules checked',
  `missing_rules_found` int DEFAULT 0 COMMENT 'Rules missing on device',
  `extra_rules_found` int DEFAULT 0 COMMENT 'Unknown rules on device',
  `rules_reapplied` int DEFAULT 0 COMMENT 'Rules re-added to device',
  `rules_removed` int DEFAULT 0 COMMENT 'Extra rules removed',
  `drift_detected` tinyint(1) DEFAULT 0 COMMENT 'Whether drift was detected',
  `error_message` TEXT COMMENT 'Error message if failed',
  `details` MEDIUMTEXT COMMENT 'Detailed reconciliation results (JSON)',
  PRIMARY KEY (`id`),
  KEY `idx_reconciliation_network` (`network_id`),
  KEY `idx_reconciliation_timestamp` (`started`),
  CONSTRAINT `fk_reconciliation_network_id` FOREIGN KEY (`network_id`) REFERENCES `networks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- =====================================================
-- 5. VNF Broker Communication Audit
-- =====================================================
-- Logs communication attempts between CloudStack and VNF (for debugging/audit)
CREATE TABLE IF NOT EXISTS `vnf_broker_audit` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `vnf_appliance_id` bigint unsigned NOT NULL,
  `operation` varchar(100) NOT NULL COMMENT 'Operation attempted (e.g., Firewall.create)',
  `method` varchar(10) COMMENT 'HTTP method or SSH',
  `endpoint` varchar(500) COMMENT 'API endpoint or CLI command',
  `request_timestamp` datetime NOT NULL,
  `response_timestamp` datetime,
  `status_code` int COMMENT 'HTTP status or exit code',
  `success` tinyint(1) DEFAULT 0,
  `error_message` TEXT,
  `duration_ms` int COMMENT 'Request duration in milliseconds',
  PRIMARY KEY (`id`),
  KEY `idx_audit_vnf_id` (`vnf_appliance_id`),
  KEY `idx_audit_timestamp` (`request_timestamp`),
  CONSTRAINT `fk_audit_vnf_id` FOREIGN KEY (`vnf_appliance_id`) REFERENCES `vnf_appliances` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- =====================================================
-- 6. Network Details Extension
-- =====================================================
-- Add columns to networks table to track VNF usage
ALTER TABLE `networks`
ADD COLUMN `vnf_enabled` tinyint(1) DEFAULT 0 COMMENT 'Whether this network uses VNF',
ADD COLUMN `vnf_template_id` bigint unsigned COMMENT 'VNF template for this network',
ADD COLUMN `vnf_dictionary_override` tinyint(1) DEFAULT 0 COMMENT 'Whether network has custom dictionary',
ADD KEY `idx_networks_vnf_template` (`vnf_template_id`);

-- =====================================================
-- 7. Template Details for VNF Configuration
-- =====================================================
-- CloudStack already has template_details table, but ensure VNF-specific keys
-- These are typically added via API/UI, but documenting expected keys:
-- 
-- INSERT INTO template_details (template_id, name, value, display) VALUES
-- (?, 'VNF_ENABLED', 'true', 1),
-- (?, 'SSH_USER', 'admin', 1),
-- (?, 'SSH_PASSWORD', '<encrypted>', 0),  -- encrypted by CloudStack
-- (?, 'WEB_USER', 'admin', 1),
-- (?, 'WEB_PASSWORD', '<encrypted>', 0),
-- (?, 'API_KEY', '<encrypted>', 0),
-- (?, 'API_TOKEN', '<encrypted>', 0),
-- (?, 'SSH_PORT', '22', 1),
-- (?, 'HTTPS_PORT', '443', 1),
-- (?, 'NIC0_ROLE', 'public', 1),
-- (?, 'NIC1_ROLE', 'guest', 1),
-- (?, 'VENDOR', 'pfSense', 1),
-- (?, 'ICON_URL', 'https://...', 1);

-- =====================================================
-- 8. Configuration Settings
-- =====================================================
-- Global settings for VNF framework (added to configuration table)
INSERT INTO `configuration` (`category`, `instance`, `component`, `name`, `value`, `description`, `default_value`, `updated`, `scope`, `is_dynamic`)
VALUES 
('Advanced', 'DEFAULT', 'management-server', 'vnf.broker.enabled', 'true', 
 'Enable VNF broker communication via Virtual Router', 'true', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.broker.port', '8443', 
 'Port for VNF broker service on Virtual Router', '8443', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.broker.mtls.enabled', 'true', 
 'Enable mutual TLS for VNF broker communication', 'true', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.broker.jwt.expiry.seconds', '300', 
 'JWT token expiry time in seconds', '300', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.request.timeout.seconds', '30', 
 'Timeout for VNF API/CLI requests', '30', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.reconciliation.enabled', 'true', 
 'Enable automatic reconciliation for VNF-backed networks', 'true', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.reconciliation.interval.minutes', '15', 
 'Interval between reconciliation runs in minutes', '15', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.reconciliation.auto.fix', 'true', 
 'Automatically fix missing rules during reconciliation', 'true', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.reconciliation.remove.unknown', 'false', 
 'Automatically remove unknown rules from VNF devices', 'false', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.health.check.enabled', 'true', 
 'Enable periodic health checks for VNF appliances', 'true', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.health.check.interval.minutes', '5', 
 'Interval between VNF health checks in minutes', '5', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.max.retry.attempts', '3', 
 'Maximum retry attempts for failed VNF operations', '3', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.retry.backoff.multiplier', '2.0', 
 'Exponential backoff multiplier for retries', '2.0', NULL, 'Global', 1),

('Advanced', 'DEFAULT', 'management-server', 'vnf.audit.retention.days', '90', 
 'Number of days to retain VNF broker audit logs', '90', NULL, 'Global', 1)
ON DUPLICATE KEY UPDATE description=VALUES(description);

-- =====================================================
-- 9. Indexes for Performance
-- =====================================================
CREATE INDEX idx_vnf_dictionaries_removed ON vnf_dictionaries(removed);
CREATE INDEX idx_vnf_appliances_state ON vnf_appliances(state);
CREATE INDEX idx_vnf_appliances_health ON vnf_appliances(health_status);
CREATE INDEX idx_vnf_appliances_last_contact ON vnf_appliances(last_contact);
CREATE INDEX idx_firewall_rules_external_id ON firewall_rules(external_id);
CREATE INDEX idx_port_forwarding_external_id ON port_forwarding_rules(external_id);

-- =====================================================
-- 10. Views for Monitoring
-- =====================================================
CREATE OR REPLACE VIEW vnf_health_summary AS
SELECT 
    n.uuid as network_uuid,
    n.name as network_name,
    va.uuid as vnf_uuid,
    va.state as vnf_state,
    va.health_status,
    va.last_contact,
    TIMESTAMPDIFF(MINUTE, va.last_contact, NOW()) as minutes_since_contact,
    vt.name as template_name,
    vd.vendor,
    vd.product
FROM vnf_appliances va
JOIN networks n ON va.network_id = n.id
JOIN vm_template vt ON va.template_id = vt.id
LEFT JOIN vnf_dictionaries vd ON va.dictionary_id = vd.id
WHERE va.removed IS NULL
  AND n.removed IS NULL;

CREATE OR REPLACE VIEW vnf_drift_summary AS
SELECT 
    n.uuid as network_uuid,
    n.name as network_name,
    vrl.started as last_reconciliation,
    vrl.status as reconciliation_status,
    vrl.drift_detected,
    vrl.missing_rules_found,
    vrl.extra_rules_found,
    vrl.rules_reapplied
FROM networks n
JOIN vnf_appliances va ON n.id = va.network_id
LEFT JOIN vnf_reconciliation_log vrl ON vrl.network_id = n.id
WHERE n.vnf_enabled = 1
  AND n.removed IS NULL
  AND vrl.id = (
    SELECT id FROM vnf_reconciliation_log 
    WHERE network_id = n.id 
    ORDER BY started DESC 
    LIMIT 1
  );

-- =====================================================
-- End of VNF Framework Schema
-- =====================================================
