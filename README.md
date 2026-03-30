# mcsquared.ai Developer Setup

One-command setup for developer workstations + CodingMachines coding agent swarm.

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
3. **Builds CodingMachines CLI** for your OS/architecture
4. **Configures connection** to `codingmachines.mcsquared.cloud`
5. **Creates helper commands**:
   - `codingmachines` — CLI (list, run, stop VMs)
   - `codingmachines-start` — boot the host VM
   - `codingmachines-stop` — stop to save money
   - `codingmachines-status` — check host + daemon
   - `codingmachines-ssh` — SSH into a micro-VM
   - `codingmachines-swarm` — launch parallel coding agents

## Usage

```bash
# Check host VM status
codingmachines-status

# Start host VM if stopped (~30s boot)
codingmachines-start

# Spawn a micro-VM
codingmachines run --name "my-task" --no-tailscale

# SSH into a running VM (see SSH_ACCESS.md for full setup)
codingmachines-ssh 10.0.100.2

# Run a command inside a VM via SSH
codingmachines-ssh 10.0.100.2  # then run commands interactively

# Launch a coding swarm (parallel agents)
codingmachines-swarm task1.md task2.md task3.md

# Stop when done
codingmachines stop <task-id>

# List all tasks
codingmachines list
```

## Architecture

```
Your Laptop (Mac/Win/Linux)
  └── codingmachines CLI (wraps Stockyard)
       └── gRPC → codingmachines.mcsquared.cloud:65433
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

## SSH Access to VMs

See [SSH_ACCESS.md](SSH_ACCESS.md) for:
- One-time SSH setup (key + config)
- Jumping into micro-VMs from your laptop
- Delivering coding prompts via SSH
- Why vsock doesn't work on GCP nested virtualization

## Admin Guide

See [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for:
- GCP host VM provisioning
- Stockyard daemon installation
- SSH key injection into VM rootfs
- Network bridge + NAT for VM internet
- Systemd services (auto-start on boot)
- Secrets management
- DNS setup (codingmachines.mcsquared.cloud)
- GCP org policy requirements

## Naming

**CodingMachines** is the mcsquared.ai branded name for the coding agent
swarm infrastructure. Under the hood it wraps
[Stockyard](https://github.com/prime-radiant-inc/stockyard), a Firecracker
micro-VM orchestrator by Prime Radiant Inc (used under its published terms).
