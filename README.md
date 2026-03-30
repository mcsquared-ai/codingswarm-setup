# CodingMachines — mcsquared.ai Coding Agent Swarm

One-command setup for developer workstations. Gives you a fleet of isolated
micro-VMs running Claude Code agents in parallel on shared GCP infrastructure.

## Developer Quickstart

### Step 1: Install (one-time)

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/codingswarm-setup/main/setup.sh | bash
```

**Windows (PowerShell as Admin):**
```powershell
irm https://raw.githubusercontent.com/mcsquared-ai/codingswarm-setup/main/setup.ps1 | iex
```

This installs dev tools, builds the CLI, and configures your connection to
`codingmachines.mcsquared.cloud`. Open a **new terminal** when done.

### Step 2: Authenticate (one-time)

```bash
gcloud auth login                              # GCP access
gcloud config set project sales-demos-485118   # set project
gh auth login                                  # GitHub access
```

### Step 3: Start the host

```bash
codingmachines-start     # boots GCP Spot VM (~30s)
codingmachines-status    # verify it's running
```

### Step 4: Use it

```bash
# Spawn a micro-VM
codingmachines run --name "my-task"
# List running VMs
codingmachines list

# SSH into a VM
codingmachines-ssh 10.0.100.2

# Launch a parallel coding swarm from prompt files
codingmachines-swarm prompts/task-a.md prompts/task-b.md prompts/task-c.md

# Stop a VM
codingmachines stop <task-id>

# Stop the host when done (saves money)
codingmachines-stop
```

## Commands Reference

| Command | What it does |
|---------|-------------|
| `codingmachines list` | List all micro-VMs (running + stopped) |
| `codingmachines run --name <name>` | Spawn a new micro-VM |
| `codingmachines stop <task-id>` | Stop a VM (workspace preserved) |
| `codingmachines destroy --force <task-id>` | Delete a VM and its workspace |
| `codingmachines-start` | Boot the GCP host VM |
| `codingmachines-stop` | Shut down the GCP host VM |
| `codingmachines-status` | Check host VM + daemon status |
| `codingmachines-ssh <vm-ip>` | SSH into a micro-VM |
| `codingmachines-swarm <file1.md> ...` | Launch parallel coding agents |

## Architecture

```
Your Laptop (Mac/Win/Linux)
  └── codingmachines CLI
       └── gRPC → codingmachines.mcsquared.cloud:65433
            └── GCP Spot VM ($0.05/hr, auto-stops after 30min idle)
                 └── Firecracker micro-VMs (6s boot, ZFS copy-on-write)
                      ├── Agent 1: claude-code working on task A
                      ├── Agent 2: claude-code working on task B
                      └── Agent 3: claude-code working on task C
```

Each micro-VM gets:
- 2 CPU cores, 4GB RAM (configurable with `--cpus` / `--memory`)
- Full internet access (NAT through host)
- Secrets injected at boot (Anthropic API key, GitHub token, etc.)
- Isolated filesystem (ZFS snapshot for audit trail)

## SSH Access

VMs are accessed via SSH over the host's bridge network. For full setup
(key download, SSH config, ProxyJump), see **[SSH_ACCESS.md](SSH_ACCESS.md)**.

Quick version:
```bash
# From your Mac (two-hop, no SSH config needed)
codingmachines-ssh 10.0.100.2

# From the host (if already SSH'd in)
ssh -i ~/.ssh/vm_key mooby@10.0.100.2
```

VM IPs start at `10.0.100.2` and increment per VM.

## Cost

| What | Cost |
|------|------|
| Host VM running | ~$0.05/hr |
| Host VM stopped | $0 (auto-stops after 30 min idle) |
| Static IP (while VM stopped) | ~$0.01/hr |
| 200GB disk | ~$20/month |
| **Typical month (3 devs, 8hr/day)** | **~$10-15** |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `connection refused` on port 65433 | Host VM is stopped. Run `codingmachines-start` |
| `dial unix .../stockyard.sock` error | `CODINGMACHINES_URL` not set. Open a new terminal or run `source ~/.codingmachines/env.sh` |
| DNS not resolving | Run `dig codingmachines.mcsquared.cloud +short` — should show `34.121.124.99` |
| SSH `Permission denied` | Download the VM key first. See [SSH_ACCESS.md](SSH_ACCESS.md) |
| Host VM won't start | GCP Spot capacity exhausted. Wait a few minutes and retry |

## More Docs

- **[SSH_ACCESS.md](SSH_ACCESS.md)** — SSH setup, jumping into VMs, delivering prompts
- **[ADMIN_GUIDE.md](ADMIN_GUIDE.md)** — Host provisioning, secrets, DNS, scaling to multiple hosts

## Naming

**CodingMachines** is the mcsquared.ai branded wrapper around
[Stockyard](https://github.com/prime-radiant-inc/stockyard), a Firecracker
micro-VM orchestrator by Prime Radiant Inc.
