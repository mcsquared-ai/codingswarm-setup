# SSH Access to CodingMachines Micro-VMs

> Micro-VMs join the Tailscale tailnet at boot. SSH directly from any
> device on your tailnet — no IAP tunnels or jump hosts needed.

## Architecture

```
Your Mac/PC (on Tailscale)
  └── SSH directly via Tailscale
       ├── stockyard-abc12345 (micro-VM 1)
       ├── stockyard-def67890 (micro-VM 2)
       └── stockyard-ghi11111 (micro-VM 3)
```

Each VM appears on your Tailscale tailnet with hostname `stockyard-<task-id>`.

## One-Time Setup (per developer)

### 1. Install Tailscale on your Mac

```bash
brew install --cask tailscale
```

Then open Tailscale from the menu bar and sign in to your tailnet.

### 2. Verify your Mac is on the tailnet

```bash
tailscale status
```

You should see your machine listed. When VMs are running, they'll appear as `stockyard-<id>`.

## Usage

### SSH into a VM

```bash
# Find running VMs
codingmachines list
tailscale status | grep stockyard-

# SSH in
codingmachines-ssh stockyard-abc12345

# Or directly
ssh mooby@stockyard-abc12345
```

### Attach to running agent

```bash
codingmachines-ssh stockyard-abc12345
tmux attach -t agent    # watch live — Ctrl+B, D to detach
```

### Run a command without interactive shell

```bash
ssh mooby@stockyard-abc12345 'uname -a'
ssh mooby@stockyard-abc12345 'cd /home/mooby/work && git log --oneline -5'
```

### Copy files to/from a VM

```bash
scp mooby@stockyard-abc12345:/home/mooby/work/data/silver/nephrologists.json .
scp local-file.py mooby@stockyard-abc12345:/home/mooby/work/
```

## Finding VMs

```bash
# List all VMs (running + stopped)
codingmachines list

# See VMs on Tailscale
tailscale status | grep stockyard-

# Full monitoring dashboard
codingmachines-monitor
```

VM hostnames follow the pattern `stockyard-<task-id>`, e.g., `stockyard-7ad72caa`.

## VM User

All VMs use the `mooby` user (UID 1001). This user has:
- Passwordless sudo
- Tailscale SSH access (key managed by Tailscale)
- Home directory at `/home/mooby`
- Secrets injected as environment variables at boot

## Sending Coding Prompts

Agents are launched by `codingmachines-swarm` which handles VM creation,
Tailscale join, prompt delivery, and tmux session setup automatically.

For manual prompt delivery:

```bash
# Copy prompt to VM
scp my-prompt.md mooby@stockyard-abc12345:/home/mooby/prompt.md

# Launch agent in tmux
ssh mooby@stockyard-abc12345 'tmux new-session -d -s agent "claude --dangerously-skip-permissions -p \"$(cat /home/mooby/prompt.md)\" 2>&1 | tee /home/mooby/agent.log"'
```

## Monitoring

```bash
codingmachines-monitor                         # all agents
codingmachines-logs stockyard-abc12345         # last 100 lines
codingmachines-logs stockyard-abc12345 -f      # stream live
codingmachines-logs stockyard-abc12345 --raw   # include JSON
```

## Why Tailscale?

Firecracker uses virtio-vsock (`/dev/vsock`) for host↔VM communication.
GCP nested virtualization does not expose `/dev/vsock`, so Stockyard's
built-in `exec` command fails. Tailscale provides a direct, encrypted
SSH path from any device on the tailnet to any VM — bypassing both
vsock and the need for bridge networking or IAP tunnels.
