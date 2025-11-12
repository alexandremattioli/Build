# File Exchange System

## Overview

The File Exchange System enables build servers to share files through GitHub, complementing the message system for larger content like logs, configurations, build artifacts, and code files.

**Key Features:**
- Share files up to 50MB between servers
- Organized by category (config, code, log, build, artifact, doc, other)
- Automatic notifications when files are shared
- Track download history for each file
- Browse and filter available files
- Git-based with automatic retry and conflict resolution

---

## Quick Start

### Share a File
```bash
# Basic usage
./scripts/share_file.sh <recipient> <category> <file_path> ["description"]

# Examples
./scripts/share_file.sh build2 config /etc/mysql/my.cnf "MySQL configuration from build1"
./scripts/share_file.sh all log /var/log/maven.log "Build failure log"
./scripts/share_file.sh build3 artifact /root/builds/app.deb "Latest DEB package"
```

### Browse Available Files
```bash
# List all files
./scripts/list_files.sh

# Filter by sender
./scripts/list_files.sh --from build1

# Filter by category
./scripts/list_files.sh --category log

# Show only undownloaded files
./scripts/list_files.sh --undownloaded

# Combine filters
./scripts/list_files.sh --from build2 --category config --limit 5
```

### Download a File
```bash
# Download to current directory
./scripts/download_file.sh file_1761920500_1234

# Download to specific directory
./scripts/download_file.sh file_1761920500_1234 /root/configs/

# Download with new filename
./scripts/download_file.sh file_1761920500_1234 /root/my_config.conf
```

---

## File Categories

| Category | Purpose | Examples |
|----------|---------|----------|
| **config** | Configuration files | my.cnf, apache2.conf, app.properties |
| **code** | Source code, scripts, patches | fix.patch, setup.sh, utils.py |
| **log** | Log files, debug output | maven.log, error.log, build.log |
| **build** | Build outputs, compiled code | app.jar, binary, Makefile |
| **artifact** | Packaged artifacts | app.deb, release.tar.gz, docker-image.tar |
| **doc** | Documentation, reports | README.md, analysis.pdf, report.txt |
| **other** | Miscellaneous files | data.json, backup.sql, notes.txt |

---

## Size Limits

| Limit | Size | Behavior |
|-------|------|----------|
| **Warning** | 10MB | Shows warning, 3-second delay to cancel |
| **Maximum** | 50MB | Hard limit, file rejected |

**Why 50MB?** GitHub performs well with files up to 50MB. Larger files slow down git operations and can cause performance issues.

**For larger files:** Consider compression, splitting, or using external storage (S3, FTP).

---

## File Sharing Workflow

### 1. Share a File

```bash
./scripts/share_file.sh build2 config /etc/mysql/my.cnf "Production MySQL settings"
```

**What happens:**
1. File validated (exists, readable, size check)
2. File copied to `shared/files/build1/config/<timestamp>_my.cnf`
3. Entry added to `shared/file_registry.json` with metadata
4. Changes committed and pushed to GitHub
5. Notification message sent to recipient with download command

**Output:**
```
════════════════════════════════════════════════════════════
Validating file: /etc/mysql/my.cnf
  Size: 1.2MB [OK]
  File is readable [OK]

Sharing file with build2...
  Category: config
  Description: Production MySQL settings

[OK] File shared successfully!
  File ID: file_1761920500_1234
  Size: 1.2MB
  Path: shared/files/build1/config/20250131_142355_my.cnf
  Download command: ./scripts/download_file.sh file_1761920500_1234

📨 Notification sent to build2
════════════════════════════════════════════════════════════
```

### 2. Recipient Receives Notification

The recipient automatically receives a message:

```
From: build1
To: build2
Subject: File shared: my.cnf

A file has been shared with you:

File ID: file_1761920500_1234
Category: config
Filename: my.cnf
Size: 1.2MB
Description: Production MySQL settings

Download with:
./scripts/download_file.sh file_1761920500_1234
```

### 3. Browse Files

```bash
./scripts/list_files.sh --undownloaded
```

**Output:**
```
════════════════════════════════════════════════════════════════════════════════
SHARED FILES
════════════════════════════════════════════════════════════════════════════════
Filters: Undownloaded only
Total files: 3
────────────────────────────────────────────────────────────────────────────────

[1] my.cnf
    ID: file_1761920500_1234
    From: build1 → To: build2
    Category: config | Size: 1.2MB | Shared: 2025-01-31T14:23:55Z
    Description: Production MySQL settings
    Downloaded by: none
    Download: ./scripts/download_file.sh file_1761920500_1234

[2] maven.log
    ID: file_1761920501_5678
    From: build3 → To: all
    Category: log | Size: 543KB | Shared: 2025-01-31T14:25:10Z
    Description: Build failure analysis
    Downloaded by: build1, build4
    Download: ./scripts/download_file.sh file_1761920501_5678
════════════════════════════════════════════════════════════════════════════════
```

### 4. Download File

```bash
./scripts/download_file.sh file_1761920500_1234 /root/configs/
```

**Output:**
```
════════════════════════════════════════════════════════════
FILE INFORMATION
════════════════════════════════════════════════════════════
  File ID: file_1761920500_1234
  From: build1
  To: build2
  Filename: my.cnf
  Category: config
  Size: 1.2MB
  Shared: 2025-01-31T14:23:55Z
  Description: Production MySQL settings
════════════════════════════════════════════════════════════

Downloading file...

[OK] File downloaded successfully!
  Location: /root/configs/my.cnf
  Size: 1.2MB

This is a configuration file. Review before using:
  cat /root/configs/my.cnf
```

---

## File Registry Structure

The `shared/file_registry.json` tracks all shared files:

```json
{
  "files": [
    {
      "id": "file_1761920500_1234",
      "from": "build1",
      "to": "build2",
      "category": "config",
      "filename": "my.cnf",
      "path": "shared/files/build1/config/20250131_142355_my.cnf",
      "size_bytes": 1258291,
      "description": "Production MySQL settings",
      "timestamp": "2025-01-31T14:23:55Z",
      "downloaded_by": [
        {
          "server": "build2",
          "timestamp": "2025-01-31T14:30:12Z"
        }
      ]
    }
  ],
  "metadata": {
    "last_cleanup": null,
    "total_size_bytes": 1258291,
    "file_count": 1
  }
}
```

**Key fields:**
- `id`: Unique file identifier (file_<timestamp>_<random>)
- `from`: Sender server ID
- `to`: Recipient server ID or "all"
- `category`: File category
- `path`: Location in repository
- `downloaded_by`: Array of servers that downloaded with timestamps

---

## Advanced Usage

### Filter by Multiple Criteria

```bash
# Config files from build1, most recent 10
./scripts/list_files.sh --from build1 --category config --limit 10

# Undownloaded logs
./scripts/list_files.sh --category log --undownloaded

# All files for build2
./scripts/list_files.sh --to build2
```

### JSON Output for Scripting

```bash
# Get JSON for programmatic use
./scripts/list_files.sh --undownloaded --format json

# Output:
{
  "total": 3,
  "files": [
    {
      "id": "file_1761920500_1234",
      "from": "build1",
      "to": "build2",
      ...
    }
  ]
}
```

### CSV Export

```bash
# Export to CSV
./scripts/list_files.sh --format csv > files.csv
```

### Overwrite Existing Files

```bash
# Download will prompt if file exists
./scripts/download_file.sh file_1761920500_1234 /root/my.cnf

# Output:
WARNING: Destination file already exists: /root/my.cnf
Overwrite? (y/N):
```

---

## Best Practices

### 1. **Use Descriptive Descriptions**
```bash
# Good
./scripts/share_file.sh build2 log /var/log/maven.log "Build failure for CloudStack 4.19.1"

# Poor
./scripts/share_file.sh build2 log /var/log/maven.log "log file"
```

### 2. **Choose the Right Category**
- Use `config` for configuration files that should be reviewed
- Use `log` for diagnostic logs
- Use `artifact` for build outputs meant for deployment
- Use `code` for source code or patches

### 3. **Compress Large Files**
```bash
# Compress before sharing
tar -czf build-logs.tar.gz /var/log/maven/*.log
./scripts/share_file.sh all log build-logs.tar.gz "All Maven logs from failed build"
```

### 4. **Clean Up Old Files**
```bash
# Periodically remove old files from shared/files/
# (Cleanup script coming soon)
```

### 5. **Check Before Downloading**
```bash
# List files first
./scripts/list_files.sh --from build3

# Then download specific file
./scripts/download_file.sh file_1761920500_1234
```

---

## Common Scenarios

### Scenario 1: Share Build Logs After Failure

```bash
# On failing build server (build2)
./scripts/share_file.sh all log /var/log/maven.log "CloudStack build failed at core module"

# Other servers can download
./scripts/list_files.sh --category log --undownloaded
./scripts/download_file.sh file_1761920500_1234
```

### Scenario 2: Distribute Configuration

```bash
# On build1 (working server)
./scripts/share_file.sh all config /etc/mysql/my.cnf "Working MySQL config for CloudStack"

# Other servers download and apply
./scripts/download_file.sh file_1761920500_1234 /etc/mysql/my.cnf
systemctl restart mysql
```

### Scenario 3: Share Build Artifacts

```bash
# On successful build server
./scripts/share_file.sh all artifact /root/builds/cloudstack-management.deb "CS 4.19.1 management DEB"

# Other servers can download for testing
./scripts/download_file.sh file_1761920500_1234 /root/packages/
```

### Scenario 4: Code Patches

```bash
# Create and share patch
git diff > fix-db-connection.patch
./scripts/share_file.sh all code fix-db-connection.patch "Fix for database connection pool issue"

# Others download and apply
./scripts/download_file.sh file_1761920500_1234
git apply fix-db-connection.patch
```

---

## Troubleshooting

### File Too Large

**Error:** `File exceeds maximum size of 50MB`

**Solutions:**
- Compress the file: `gzip large-file.log`
- Split the file: `split -b 40M large-file.log part_`
- Share only relevant portions
- Use external storage for very large files

### File Not Found After Download

**Possible causes:**
1. File was removed from repository (check with `list_files.sh`)
2. Git pull failed (run `git pull origin main` manually)
3. File path changed (check registry)

### Push Conflicts

The scripts automatically retry with exponential backoff (5 attempts). If still failing:
```bash
cd /root/Build
git pull origin main
# Resolve any conflicts
git push origin main
```

### Registry Corruption

If `file_registry.json` becomes corrupted:
```bash
# Backup current registry
cp shared/file_registry.json shared/file_registry.json.backup

# Reset to empty
echo '{"files": [], "metadata": {"last_cleanup": null, "total_size_bytes": 0, "file_count": 0}}' > shared/file_registry.json

# Commit and push
git add shared/file_registry.json
git commit -m "Reset file registry"
git push origin main
```

---

## Script Reference

### share_file.sh

**Purpose:** Share a file with another server

**Usage:**
```bash
./scripts/share_file.sh <recipient> <category> <file_path> ["description"]
```

**Arguments:**
- `recipient`: build1-4 or "all"
- `category`: config, code, log, build, artifact, doc, other
- `file_path`: Path to file to share
- `description`: Optional description (quotes required if contains spaces)

**Exit Codes:**
- 0: Success
- 1: Validation error
- 2: Git operation failed
- 3: File operation failed

### download_file.sh

**Purpose:** Download a shared file

**Usage:**
```bash
./scripts/download_file.sh <file_id> [destination_path]
```

**Arguments:**
- `file_id`: File ID from registry (file_XXXXXXXXXX_XXXX)
- `destination_path`: Optional destination (default: current directory)

**Exit Codes:**
- 0: Success
- 1: Validation error
- 2: Git operation failed
- 3: File operation failed

### list_files.sh

**Purpose:** Browse shared files

**Usage:**
```bash
./scripts/list_files.sh [options]
```

**Options:**
- `--from <server>`: Filter by sender
- `--to <server>`: Filter by recipient
- `--category <cat>`: Filter by category
- `--undownloaded`: Show only undownloaded files
- `--format <fmt>`: Output format (table, json, csv)
- `--limit <n>`: Show only N most recent files

**Exit Codes:**
- 0: Success
- 1: Validation error
- 2: Git operation failed

---

## Integration with Message System

The File Exchange System integrates seamlessly with the message system:

1. **Automatic Notifications:** When sharing a file, the recipient automatically receives a message
2. **Message Size Limits:** Messages limited to 10KB, files up to 50MB
3. **Choose Appropriately:**
   - Use **messages** for: Instructions, status updates, questions, small data
   - Use **files** for: Logs, configs, artifacts, code, large data

**Example Integration:**
```bash
# 1. Share file
./scripts/share_file.sh build2 log /var/log/maven.log "Build failure analysis"
# → Automatic notification sent

# 2. Send follow-up message
./scripts/send_message.sh build2 "Follow-up" "Please review the log file and let me know if you need the full stack trace."
```

---

## Future Enhancements

Planned features:
- [ ] Automatic cleanup of old files (age-based, size-based)
- [ ] File versioning (multiple versions of same file)
- [ ] File expiration dates
- [ ] Compression options in share_file.sh
- [ ] Batch download (download multiple files at once)
- [ ] File diff comparison
- [ ] Search files by content/metadata

---

## Summary

The File Exchange System provides:
- [OK] Easy file sharing between build servers
- [OK] Organized storage by category
- [OK] Size validation and warnings
- [OK] Automatic notifications
- [OK] Download tracking
- [OK] Multiple filtering options
- [OK] Git-based with conflict handling
- [OK] Integration with message system

**Quick Command Reference:**
```bash
# Share
./scripts/share_file.sh build2 config /etc/my.cnf "Description"

# List
./scripts/list_files.sh --undownloaded

# Download
./scripts/download_file.sh file_1761920500_1234
```

For questions or issues, check this documentation or use the message system to communicate with other build servers.
