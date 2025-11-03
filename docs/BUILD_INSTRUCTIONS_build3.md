# Build3 (ll-ACSBuilder3) - Build Instructions

## Server Information
- **Hostname**: ll-ACSBuilder3
- **IP Address**: 10.1.3.179
- **AI Manager**: TBD
- **Purpose**: CloudStack build server #3

## Hardware Specifications
- **CPU**: 32 cores (recommended)
- **RAM**: 128 GB (recommended)
- **Disk**: 500+ GB free space
- **OS**: Ubuntu 24.04 LTS

## Software Requirements

### Core Build Tools
- **Java**: OpenJDK 17
- **Maven**: 3.9.10+
- **Python**: 3.12+ (with python-is-python3)
- **Node.js**: 18.20.8+ (for UI builds)
- **MySQL**: 8.0+

### System Packages
```bash
apt-get update
apt-get install -y openjdk-17-jdk maven nodejs npm \
  mysql-server mysql-client git build-essential \
  python3 python3-pip python-is-python3 \
  genisoimage libssl-dev dpkg-dev debhelper
```

## CloudStack Repository
```bash
cd /root
git clone https://github.com/apache/cloudstack.git
cd cloudstack
git checkout 4.21
```

## Standard Build Command
```bash
cd /root/cloudstack
mvn -Dmaven.test.skip=true -P systemvm,developer clean install \
  2>&1 | tee /root/build-logs/mvn_install.log
```

## Build Coordination
This server participates in the Build coordination system. See main README.md for details.

### Setup Coordination
```bash
cd /root
git clone https://github.com/alexandremattioli/Build.git
cd Build/scripts
./setup_build3.sh
```

## DEB Package Creation
After successful Maven build:
```bash
cd /root/cloudstack
./packaging/build-deb.sh -o /root/artifacts/build3/debs/$(date -u +%Y%m%dT%H%M%SZ)
```

## SSH Access
Build3 has passwordless SSH configured to other build servers:
- Build1: `ssh root@10.1.3.175` or `ssh root@ll-ACSBuilder1`
- Build2: `ssh root@10.1.3.177` or `ssh root@ll-ACSBuilder2`
- Build4: `ssh root@10.1.3.181` or `ssh root@ll-ACSBuilder4`
