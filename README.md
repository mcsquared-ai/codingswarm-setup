# CodingMachines — mcsquared.ai Coding Agent Swarm

One-command setup for developer workstations. Gives you a fleet of isolated
micro-VMs running Claude Code agents in parallel on shared GCP infrastructure.

## Developer Quickstart

### Step 1: Install (one-time)

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/codingswarm-setup/main/codingmachines/setup.sh | bash
```

**Windows (PowerShell as Admin):**
```powershell
irm https://raw.githubusercontent.com/mcsquared-ai/codingswarm-setup/main/codingmachines/setup.ps1 | iex
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

### Step 4: Launch a coding swarm

```bash
# Launch parallel agents from prompt files
codingmachines-swarm prompts/task-a.md prompts/task-b.md prompts/task-c.md
```

Each agent runs inside a **tmux session** with output logged to `/home/mooby/agent.log`.

### Step 5: Monitor

```bash
# Dashboard: status of all running agents
codingmachines-monitor

# Tail a specific agent's live output
codingmachines-logs stockyard-<task-id> --follow

# SSH in and attach to the agent's terminal
codingmachines-ssh stockyard-<task-id>
tmux attach -t agent       # watch live — Ctrl+B, D to detach
```

### Step 6: Clean up

```bash
codingmachines stop <task-id>    # stop a VM
codingmachines-stop              # shut down host to save money
```

## Commands Reference

| Command | What it does |
|---------|-------------|
| **Launch** | |
| `codingmachines-start` | Boot the GCP host VM (~30s) |
| `codingmachines run --name <name>` | Spawn a single micro-VM |
| `codingmachines-swarm <file1.md> ...` | Launch parallel coding agents |
| **Monitor** | |
| `codingmachines-monitor` | Dashboard: status of all agents |
| `codingmachines-logs <vm-ip> [-f]` | Tail agent output from a VM |
| `codingmachines-ssh <vm-ip>` | SSH into a VM (then `tmux attach`) |
| `codingmachines list` | List all micro-VMs (running + stopped) |
| `codingmachines-status` | Check host VM + daemon health |
| **Cleanup** | |
| `codingmachines stop <task-id>` | Stop a VM (workspace preserved) |
| `codingmachines destroy --force <task-id>` | Delete a VM and its data |
| `codingmachines-stop` | Shut down the GCP host VM |

## Monitoring Agents

Each agent launched by `codingmachines-swarm` runs inside a **tmux session**
named `agent` with output logged to `/home/mooby/agent.log`.

**Quick status of all agents:**
```
$ codingmachines-monitor

Host VM: RUNNING

=== VM LIST ===
ID        NAME      STATUS   CREATED
abc123    track2a   running  2026-03-30T12:00:00Z
def456    track2b   running  2026-03-30T12:00:02Z

=== AGENT STATUS ===

--- track2a (abc123) @ stockyard-<task-id> ---
  Agent: RUNNING (tmux session active)
  Log: 1842 lines (256K)
  Process: claude-code running (01:23:45)
  Last output:
    Downloading NPI registry...
    Processing 7.2GB file...
    Found 12,847 nephrologists

--- track2b (def456) @ stockyard-<task-id-2> ---
  Agent: RUNNING (tmux session active)
  Log: 923 lines (128K)
  Process: claude-code running (01:23:42)
  Last output:
    Fetching Part D data for 2023...
```

**Three levels of visibility:**

| Level | Command | What you see |
|-------|---------|-------------|
| Overview | `codingmachines-monitor` | All agents: status, log size, last 3 lines |
| Streaming | `codingmachines-logs <ip> -f` | Live log output (like `tail -f`) |
| Full terminal | `codingmachines-ssh <ip>` then `tmux attach` | Full interactive agent terminal |

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

VMs join the Tailscale tailnet at boot. SSH directly from any device on your tailnet — no IAP tunnels or jump hosts needed. See **[SSH_ACCESS.md](codingmachines/SSH_ACCESS.md)** for full setup.

```bash
codingmachines-ssh stockyard-<task-id>    # or: ssh mooby@stockyard-<task-id>
```

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
| SSH `Permission denied` | Download the VM key first. See [SSH_ACCESS.md](codingmachines/SSH_ACCESS.md) |
| Host VM won't start | GCP Spot capacity exhausted. Wait a few minutes and retry |

## More Docs

- **[SSH_ACCESS.md](codingmachines/SSH_ACCESS.md)** — SSH setup, jumping into VMs, delivering prompts
- **[ADMIN_GUIDE.md](codingmachines/ADMIN_GUIDE.md)** — Host provisioning, secrets, DNS, scaling to multiple hosts

## Naming

**CodingMachines** is the mcsquared.ai branded wrapper around
[Stockyard](https://github.com/prime-radiant-inc/stockyard), a Firecracker
micro-VM orchestrator by Prime Radiant Inc.
