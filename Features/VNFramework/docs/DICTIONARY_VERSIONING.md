# VNF Dictionary Versioning Specification

## Overview

Dictionary versioning enables backward compatibility and migration between different vendor dictionary formats.

## Version Format

Dictionaries use semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: Backward-compatible functionality additions
- **PATCH**: Backward-compatible bug fixes

Example: `1.2.3`

## Version Field in Dictionary

```yaml
version: "1.0.0"
vendor: "Netgate"
product: "pfSense"
compatibility:
  min_broker_version: "1.0.0"  # Minimum broker version required
  deprecated: false             # Is this dictionary deprecated?
  superseded_by: null           # Version that supersedes this one
```

## Version Compatibility Matrix

| Dictionary Version | Broker Version | Compatible | Notes |
|-------------------|----------------|------------|-------|
| 1.0.x | 1.0.x | [OK] | Full compatibility |
| 1.1.x | 1.0.x | [OK] | Backward compatible (new features) |
| 2.0.x | 1.0.x | ✗ | Breaking changes |
| 1.0.x | 2.0.x | [OK] | Broker maintains backward compat |

## Version Migration Guide

### Upgrading Dictionary from 1.0 to 1.1

**Changes in 1.1:**
- Added `compatibility` section
- Added `errorCodes` mapping
- Deprecated `authType: basic` in favor of `authType: token`

**Migration steps:**

1. Add compatibility section:
```yaml
version: "1.1.0"
compatibility:
  min_broker_version: "1.0.0"
  deprecated: false
```

2. Add error code mappings:
```yaml
errorCodes:
  AUTH_FAILED:
    cloudstackCode: "VNF_AUTH"
    message: "Authentication failed"
    httpStatus: 401
```

3. Update auth configuration (if using basic auth):
```yaml
# Old (1.0)
access:
  authType: basic
  username: "${VNF_USER}"
  password: "${VNF_PASSWORD}"

# New (1.1) - still supported but deprecated
access:
  authType: token
  tokenRef: API_TOKEN
  tokenHeader: Authorization
```

### Upgrading Dictionary from 1.1 to 2.0

**Breaking changes in 2.0:**
- Removed `authType: basic` support
- Changed `services` structure to include versioned endpoints
- Added required `responseMapping.errorPath`

**Migration steps:**

1. Update version and mark 1.1 as superseded:
```yaml
# Old dictionary (1.1.0)
version: "1.1.0"
compatibility:
  deprecated: true
  superseded_by: "2.0.0"

# New dictionary (2.0.0)
version: "2.0.0"
compatibility:
  min_broker_version: "2.0.0"
```

2. Convert to token-only auth (remove basic auth):
```yaml
access:
  authType: token
  tokenRef: API_TOKEN
  tokenHeader: Authorization
```

3. Add error paths to all operations:
```yaml
services:
  Firewall:
    create:
      method: POST
      endpoint: /firewall/rule
      responseMapping:
        successCode: 201
        idPath: $.data.id
        errorPath: $.message  # Required in 2.0
```

## Broker Version Detection

The broker can detect dictionary version and apply appropriate parsing:

```python
def load_dictionary(path: str) -> Dict:
    """Load dictionary with version-aware parsing"""
    with open(path, 'r') as f:
        raw_dict = yaml.safe_load(f)
    
    version = raw_dict.get('version', '1.0.0')
    major_version = int(version.split('.')[0])
    
    if major_version == 1:
        return parse_v1_dictionary(raw_dict)
    elif major_version == 2:
        return parse_v2_dictionary(raw_dict)
    else:
        raise ValueError(f"Unsupported dictionary version: {version}")
```

## Deprecation Policy

1. **Announcement**: Deprecation announced in documentation
2. **Grace Period**: Minimum 6 months support after deprecation
3. **Warning Logs**: Broker logs warnings when using deprecated dictionaries
4. **Removal**: After grace period, old version support removed

## Version Check at Runtime

The broker validates dictionary version compatibility at startup:

```python
def validate_version_compatibility(dict_version: str, broker_version: str) -> bool:
    """Check if dictionary is compatible with broker"""
    dict_major = int(dict_version.split('.')[0])
    broker_major = int(broker_version.split('.')[0])
    
    # Major version must match or broker major must be higher
    if dict_major > broker_major:
        return False
    
    # Check min_broker_version if specified
    min_broker = dictionary.get('compatibility', {}).get('min_broker_version')
    if min_broker and compare_versions(broker_version, min_broker) < 0:
        return False
    
    return True
```

## Example: Complete Versioned Dictionary

```yaml
# VNF Dictionary v1.1.0
version: "1.1.0"
vendor: "Netgate"
product: "pfSense"
firmware_version: "2.7+"

compatibility:
  min_broker_version: "1.0.0"
  deprecated: false
  superseded_by: null

access:
  protocol: https
  port: 443
  basePath: /api/v1
  authType: token
  tokenRef: API_TOKEN
  tokenHeader: Authorization

services:
  Firewall:
    create:
      method: POST
      endpoint: /firewall/rule
      headers:
        Content-Type: application/json
      body: |
        {
          "interface": "wan",
          "type": "pass",
          "protocol": "${protocol}",
          "src": "${sourceCidr}",
          "dst": "any",
          "dstport": "${startPort}"
        }
      responseMapping:
        successCode: 201
        idPath: $.data.id
        errorPath: $.message

errorCodes:
  AUTH_FAILED:
    cloudstackCode: "VNF_AUTH"
    message: "Authentication failed"
    httpStatus: 401
  INVALID_REQUEST:
    cloudstackCode: "VNF_INVALID"
    message: "Invalid request parameters"
    httpStatus: 400
  RESOURCE_NOT_FOUND:
    cloudstackCode: "VNF_INVALID"
    message: "Resource not found"
    httpStatus: 404
```

## Testing Versions

Test dictionary compatibility:

```bash
# Validate specific version
python3 dictionary_validator.py --schema schemas/vnf-dictionary-schema-v1.json \
  dictionaries/pfsense-dictionary-v1.0.yaml

# Check version compatibility
python3 check_version_compatibility.py \
  --dict-version 1.1.0 \
  --broker-version 1.0.0
```

## Version Migration Tool

```bash
# Migrate dictionary from v1.0 to v1.1
python3 migrate_dictionary.py \
  --input dictionaries/pfsense-v1.0.yaml \
  --output dictionaries/pfsense-v1.1.yaml \
  --target-version 1.1.0
```

## Changelog Format

Each dictionary should include a changelog in the repository:

```markdown
# pfSense Dictionary Changelog

## [1.1.0] - 2025-11-07
### Added
- Error code mappings for VNF_AUTH, VNF_INVALID
- Compatibility section with min_broker_version
- Response error path mapping

### Deprecated
- Basic authentication (use token authentication)

### Changed
- Updated response mapping to include errorPath

## [1.0.0] - 2025-11-04
### Added
- Initial release
- Firewall rule operations
- NAT rule operations
- VPN configuration support
```
