# Updated Section for README.md - Add after line 13

## For Build3 - `root@ll-ACSBuilder3`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build3.sh
```

## For Build4 - `root@ll-ACSBuilder4`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build4.sh
```

---

## Updated Server List

This repository serves as a file-based communication and coordination system between:
- **Build1** (`root@ll-ACSBuilder1`, 10.1.3.175) - Managed by Codex
- **Build2** (`root@ll-ACSBuilder2`, 10.1.3.177) - Managed by GitHub Copilot
- **Build3** (`root@ll-ACSBuilder3`, 10.1.3.179) - Managed by TBD
- **Build4** (`root@ll-ACSBuilder4`, 10.1.3.181) - Managed by TBD

### Direct SSH Access
All servers have passwordless SSH configured between each other:
- Build1: `ssh root@10.1.3.175` or `ssh root@ll-ACSBuilder1`
- Build2: `ssh root@10.1.3.177` or `ssh root@ll-ACSBuilder2`
- Build3: `ssh root@10.1.3.179` or `ssh root@ll-ACSBuilder3`
- Build4: `ssh root@10.1.3.181` or `ssh root@ll-ACSBuilder4`

### Updated File Structure
```
/
├── README.md                    # This file
├── METHODOLOGY.md               # Detailed protocol specification
├── build1/
│   ├── status.json             # Build1 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
├── build2/
│   ├── status.json             # Build2 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
├── build3/
│   ├── status.json             # Build3 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
├── build4/
│   ├── status.json             # Build4 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
├── coordination/
│   ├── jobs.json               # Job queue
│   ├── locks.json              # Coordination locks
│   └── messages.json           # Inter-server messages
└── shared/
    ├── build_config.json       # Shared build configuration
    └── health_dashboard.json   # Aggregate health status
```

### Updated Status File Format

Each server maintains a `status.json` file:
```json
{
  "server": "build1|build2|build3|build4",
  "ip": "10.1.3.x",
  "manager": "Codex|GitHub Copilot|TBD",
  ...
}
```
