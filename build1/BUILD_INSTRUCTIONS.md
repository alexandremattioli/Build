# Apache CloudStack 4.21 Build Instructions - Build1 (Codex)

**Server**: Build1 - `root@ll-ACSBuilder1` (10.1.3.175)  
**Manager**: Codex  
**Branch**: ExternalNew  
**Last Updated**: 2025-10-29

---

## Server Identification

- **Hostname**: `ll-ACSBuilder1`
- **Shell Prompt**: `root@ll-ACSBuilder1`
- **IP Address**: 10.1.3.175
- **Manager**: Codex
- **Partner Server**: Build2 (`root@ll-ACSBuilder2`, 10.1.3.177, managed by GitHub Copilot)

---

## Build Environment (Agreed with Build2)

These specifications were agreed upon with Build2 (GitHub Copilot) on 2025-10-29.

### Java
- **Primary**: OpenJDK 17 (default)
- **JAVA_HOME**: `/usr/lib/jvm/java-17-openjdk-amd64`
- **Secondary**: OpenJDK 11 (may be present)

### Maven
- **Version**: 3.9.10
- **M2_HOME**: `/usr/share/maven`
- **MAVEN_OPTS**: `-Xms2g -Xmx12g -XX:ActiveProcessorCount=32 -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxMetaspaceSize=1024m`

### Node.js
- **Version**: 18.20.8 (NodeSource LTS)
- **npm**: From NodeSource
- **NODE_OPTIONS**: `--max-old-space-size=8192`

### Database
- **Type**: MySQL 8.0 only (no MariaDB)
- **Root Password**: `ACS421!mysql`
- **Config**: Stored in `/root/.my.cnf` (chmod 600)

### Python
Required packages:
- python3, python3-dev, python3-setuptools, python3-venv, python3-pip
- python3-openssl, python3-mysql.connector, python3-mysqldb

### Build Tools
- git, build-essential, debhelper, dpkg-dev, devscripts, fakeroot
- lsb-release, genisoimage, libssl-dev, libffi-dev
- dh-systemd (via debhelper >= 13)

### Runtime Dependencies
Per debian/control:
- net-tools, sudo, adduser, bzip2, file, gawk, iproute2, ipmitool
- nfs-common, qemu-utils, rng-tools5, augeas-tools, uuid-runtime
- openipmi, rpcbind, freeipmi-common, libfreeipmi17, keyutils
- python3-dnspython, python3-netaddr

### Hardware
- **CPU**: 32 cores
- **RAM**: 128 GB
- **Optimizations**: Configured for parallel builds

---

## Repository Setup

### Source Location
```bash
/root/cloudstack-ExternalNew
```

### Initial Clone (if needed)
```bash
cd /root
git clone https://github.com/apache/cloudstack.git cloudstack-ExternalNew
cd cloudstack-ExternalNew
git checkout ExternalNew
```

### Update to Latest
```bash
cd /root/cloudstack-ExternalNew
git fetch origin ExternalNew
git reset --hard origin/ExternalNew
git rev-parse HEAD > /root/build-logs/build_commit.txt
```

---

## Build Process

### 1. Environment Setup

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export M2_HOME=/usr/share/maven
export MAVEN_OPTS="-Xms2g -Xmx12g -XX:ActiveProcessorCount=32 -XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxMetaspaceSize=1024m"
export NODE_OPTIONS=--max-old-space-size=8192
```

### 2. Validate Environment

```bash
java -version    # Should show OpenJDK 17
mvn -v          # Should show Maven 3.9.10
node -v         # Should show v18.20.8
mysql --version # Should show MySQL 8.0
```

### 3. Maven Build

**Standard Build (recommended):**
```bash
cd /root/cloudstack-ExternalNew
mvn -Pdeveloper -DskipTests clean install | tee /root/build-logs/mvn_developer.log
```

**With SystemVM artifacts (optional):**
```bash
mvn -Psystemvm -DskipTests clean package | tee /root/build-logs/mvn_systemvm.log
```

**With non-redistributable plugins (optional):**
```bash
cd deps && ./install-non-oss.sh
mvn -Pdeveloper,systemvm -Dnoredist -DskipTests clean install
```

### 4. Build Dependencies

```bash
cd /root/cloudstack-ExternalNew
mvn -P deps | tee /root/build-logs/mvn_deps.log
```

### 5. Debian Package Creation

```bash
cd /root/cloudstack-ExternalNew
dpkg-buildpackage -uc -us | tee /root/build-logs/dpkg_build.log
```

**Note**: Debian packages will be created in `/root/` (one level up from source)

### 6. Artifact Verification

```bash
cd /root
sha256sum cloudstack_*.deb > /root/build-logs/deb_sha256.txt
ls -lh cloudstack_*.deb
```

**Find JAR files:**
```bash
find /root/cloudstack-ExternalNew -maxdepth 3 -name "*.jar" > /root/build-logs/jar_manifest.txt
```

---

## Build Logs

All logs are stored in:
```bash
/root/build-logs/
```

### Log Files
- `build_commit.txt` - Git commit SHA being built
- `mvn_developer.log` - Maven developer profile build
- `mvn_systemvm.log` - Maven systemvm build (if run)
- `mvn_deps.log` - Maven dependencies build
- `dpkg_build.log` - Debian packaging output
- `deb_sha256.txt` - SHA256 checksums of DEBs
- `jar_manifest.txt` - List of JAR files created

---

## Expected Output

### Debian Packages (in /root/)
- `cloudstack-common_4.21.0.0_all.deb`
- `cloudstack-management_4.21.0.0_all.deb`
- `cloudstack-agent_4.21.0.0_all.deb`
- `cloudstack-usage_4.21.0.0_all.deb`
- `cloudstack-ui_4.21.0.0_all.deb`
- Additional packages as per build configuration

---

## Communication with Build2

### Send Status Updates
```bash
cd /root/Build/scripts
./update_status.sh build1 building job_123
./update_status.sh build1 success
./update_status.sh build1 failed
```

### Send Messages
```bash
cd /root/Build/scripts
./send_message.sh build1 build2 info "Build Started" "Building commit abc123"
./send_message.sh build1 build2 info "Build Complete" "DEBs ready"
./send_message.sh build1 all error "Build Failed" "Check logs"
```

### Check Messages from Build2
```bash
cd /root/Build/scripts
./read_messages.sh build1
```

### Check Overall Health
```bash
cd /root/Build/scripts
./check_health.sh
```

---

## Troubleshooting

### Build Failures

**Maven out of memory:**
- Increase MAVEN_OPTS heap size: `-Xmx16g` or higher
- Check available RAM: `free -h`

**Node.js heap errors:**
- Increase NODE_OPTIONS: `--max-old-space-size=12288`

**Git conflicts:**
```bash
cd /root/cloudstack-ExternalNew
git fetch origin ExternalNew
git reset --hard origin/ExternalNew
```

**Missing dependencies:**
```bash
sudo apt update
sudo apt install -f
```

### Package Issues

**dpkg-buildpackage fails:**
- Check debian/control dependencies
- Verify debhelper version: `dpkg -l | grep debhelper`
- Review dpkg_build.log for specific errors

**DEBs not created:**
- Verify Maven build completed successfully
- Check mvn_developer.log for errors
- Ensure mvn -P deps completed

---

## Differences from Build2

Build1 and Build2 use the same agreed-upon environment and build process.
Any intentional differences should be documented here and communicated via
the coordination repository.

**Current Status**: Fully aligned with Build2 specifications.

**Note**: Build1 uses `/root/cloudstack-ExternalNew` while Build2 uses 
`/root/src/cloudstack` for the source directory.

---

## Notes

- The Debian packaging flow (`dpkg-buildpackage`) invokes required Maven
  packaging steps and UI build as defined in `debian/rules`
- Standalone UI build (`ui/npm install && ui/npm run build`) is generally
  unnecessary unless doing UI-only development
- For integration tests or hypervisor-specific validation, install optional
  packages as needed for your target environment

---

## Version History

- **2025-10-29**: Initial build instructions aligned with Build2 (GitHub Copilot)
- Environment specifications agreed and documented
- Communication framework integrated

---

## References

- Build coordination: https://github.com/alexandremattioli/Build
- Partner server: Build2 (`root@ll-ACSBuilder2`)
- Source repository: https://github.com/apache/cloudstack (ExternalNew branch)
- Local source: `/root/cloudstack-ExternalNew`
