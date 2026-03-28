# mcsquared.ai Developer Setup

One-command setup for developer workstations + Stockyard coding agent swarm.

## Quick Start

### macOS / Linux
```bash
curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/dev-setup/main/setup.sh | bash
```

### Windows (PowerShell as Admin)
```powershell
irm https://raw.githubusercontent.com/mcsquared-ai/dev-setup/main/setup.ps1 | iex
```

## What It Does

1. **Detects your platform** (macOS arm64/amd64, Linux x86_64, Windows WSL2)
2. **Installs dev tools**: git, go, gcloud, gh, python, uv, node
3. **Builds Stockyard CLI** for your OS/architecture
4. **Configures connection** to the shared GCP coding farm
5. **Creates helper commands**:
   - `stockyard-start` — boot the host VM
   - `stockyard-stop` — stop to save money
   - `stockyard-status` — check host + daemon
   - `stockyard-swarm` — launch parallel coding agents

## Usage

```bash
# Check host VM status
stockyard-status

# Start host VM if stopped (~30s boot)
stockyard-start

# Spawn a micro-VM
stockyard run --name "my-task" --no-tailscale

# Run commands inside it
stockyard exec <task-id> -- git clone https://github.com/mcsquared-ai/my-repo
stockyard exec <task-id> -- claude-code -p "implement feature X"

# Launch a coding swarm (parallel agents)
stockyard-swarm task1.md task2.md task3.md

# Stop when done
stockyard stop <task-id>

# List all tasks
stockyard list
```

## Architecture

```
Your Laptop (Mac/Win/Linux)
  └── stockyard CLI (17MB)
       └── gRPC → 34.121.124.99:65433
            └── GCP Spot VM ($0.05/hr, auto-stops after 30min idle)
                 └── Firecracker micro-VMs (6s boot, ZFS CoW clones)
                      ├── Agent 1: working on project A
                      ├── Agent 2: working on project B
                      └── Agent 3: working on project C
```

## Cost

| What | Cost |
|------|------|
| Host VM running | ~$0.05/hr |
| Host VM stopped | $0 (auto-stops after 30 min idle) |
| Typical month (3 devs, 8hr/day) | ~$10-15 |

## Admin Guide

See [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for:
- GCP host VM provisioning
- Stockyard daemon installation
- Secrets management
- GCP org policy requirements
