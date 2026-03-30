# CodingMachines — Admin Setup Guide

> Version: 2.0 | Date: 2026-03-30
> Model: Local Machine → GCP Host VM → Firecracker Micro-VMs (Coding Swarm)
> Branded as: **CodingMachines** (wraps [Stockyard](https://github.com/prime-radiant-inc/stockyard))

## Architecture

```
┌─────────────────┐
│  Developer Mac   │
│  or Windows PC   │──── gRPC (port 65433) ────┐
│                  │                            │
│  codingmachines  │                            ▼
└─────────────────┘                    ┌──────────────────┐
                                       │  GCP Spot VM      │
┌─────────────────┐                    │  (codingmachines) │
│  Developer 2     │──── gRPC ─────────│                    │
│  Mac/Windows     │                    │  stockyardd        │
└─────────────────┘                    │  ├── micro-VM 1    │
                                       │  ├── micro-VM 2    │
┌─────────────────┐                    │  ├── micro-VM 3    │
│  Developer 3     │──── gRPC ─────────│  ├── ...           │
│  Mac/Windows     │                    │  └── micro-VM N    │
└─────────────────┘                    │                    │
                                       │  ZFS pool (CoW)    │
                                       │  100GB, compressed │
                                       │  Auto-stop: 30min  │
                                       └──────────────────┘
```

## Prerequisites

### All Platforms
- Google Cloud SDK (`gcloud`) — https://cloud.google.com/sdk/docs/install
- Go 1.22+ — https://go.dev/dl/
- Git
- GitHub account with access to repos

### macOS
```bash
brew install google-cloud-sdk go git
```

### Windows
```powershell
# Install via winget
winget install Google.CloudSDK
winget install GoLang.Go
winget install Git.Git
```

### Linux
```bash
sudo apt install -y golang-go git
# Follow https://cloud.google.com/sdk/docs/install for gcloud
```

## Step 1: GCP Authentication

```bash
# Login to GCP (opens browser)
gcloud auth login

# Set project
gcloud config set project sales-demos-485118
```

## Step 2: Start the Host VM (if stopped)

The Stockyard host auto-stops after 30 minutes idle. To restart:

```bash
# Check status
gcloud compute instances describe codingmachines \
  --zone=us-central1-a --format='value(status)'

# Start if stopped
gcloud compute instances start codingmachines --zone=us-central1-a

# Wait ~30 seconds for boot, then verify daemon
# (daemon auto-starts via systemd — see Admin Setup below)
```

**DNS**: `codingmachines.mcsquared.cloud` → `34.121.124.99` (static IP, never changes)

## Step 3: Install CodingMachines CLI (one-time per developer)

> Developers should use the automated setup script instead of these manual steps:
> `curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/codingswarm-setup/main/setup.sh | bash`

### macOS (Apple Silicon)
```bash
cd /tmp
git clone https://github.com/prime-radiant-inc/stockyard.git
cd stockyard
GOOS=darwin GOARCH=arm64 go build -o stockyard ./cmd/stockyard
mkdir -p ~/.local/bin
cp stockyard ~/.local/bin/
chmod +x ~/.local/bin/stockyard
```

### macOS (Intel)
```bash
cd /tmp
git clone https://github.com/prime-radiant-inc/stockyard.git
cd stockyard
GOOS=darwin GOARCH=amd64 go build -o stockyard ./cmd/stockyard
mkdir -p ~/.local/bin
cp stockyard ~/.local/bin/
chmod +x ~/.local/bin/stockyard
```

### Windows (PowerShell)
```powershell
cd $env:TEMP
git clone https://github.com/prime-radiant-inc/stockyard.git
cd stockyard
$env:GOOS="windows"; $env:GOARCH="amd64"
go build -o stockyard.exe ./cmd/stockyard
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin"
Copy-Item stockyard.exe "$env:USERPROFILE\.local\bin\"
# Add to PATH: [Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$env:USERPROFILE\.local\bin", "User")
```

### Linux (x86_64)
```bash
cd /tmp
git clone https://github.com/prime-radiant-inc/stockyard.git
cd stockyard
GOOS=linux GOARCH=amd64 go build -o stockyard ./cmd/stockyard
mkdir -p ~/.local/bin
cp stockyard ~/.local/bin/
chmod +x ~/.local/bin/stockyard
```

## Step 4: Configure Client (one-time per developer)

### macOS / Linux
```bash
# Create config
mkdir -p ~/.codingmachines
cat > ~/.codingmachines/env.sh << 'EOF'
export CODINGMACHINES_URL=grpc://codingmachines.mcsquared.cloud:65433
export CODINGMACHINES_HOST=codingmachines.mcsquared.cloud
export STOCKYARD_URL=$CODINGMACHINES_URL  # required by underlying Stockyard binary
export PATH=$PATH:$HOME/.local/bin
EOF

# Add to shell profile
echo 'source ~/.codingmachines/env.sh' >> ~/.zshrc  # macOS
# OR
echo 'source ~/.codingmachines/env.sh' >> ~/.bashrc  # Linux
```

### Windows (PowerShell)
```powershell
# Set environment variables permanently
[Environment]::SetEnvironmentVariable("CODINGMACHINES_URL", "grpc://codingmachines.mcsquared.cloud:65433", "User")
[Environment]::SetEnvironmentVariable("STOCKYARD_URL", "grpc://codingmachines.mcsquared.cloud:65433", "User")  # required by underlying binary
[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$env:USERPROFILE\.local\bin", "User")
```

## Step 5: Verify Connection

```bash
codingmachines list
# Expected output: "No tasks found" (or list of running tasks)
```

## Usage

### Spawn a Micro-VM
```bash
# Basic: 2 CPU, 4GB RAM
codingmachines run --name "my-task" --no-tailscale

# Custom resources
codingmachines run --name "heavy-build" --cpus 4 --memory 8G --no-tailscale
```

### SSH into a VM
```bash
# List VMs to find IPs
codingmachines list

# SSH in (helper script)
codingmachines-ssh 10.0.100.2

# Or manually from the host
ssh -i ~/.ssh/vm_key mooby@10.0.100.2
```

> **Note**: `codingmachines exec` (aka `stockyard exec`) uses vsock which is
> broken on GCP nested virtualization. Use SSH instead. See [SSH_ACCESS.md](SSH_ACCESS.md).

### Coding Swarm (multiple agents in parallel)
```bash
# Launch a swarm from prompt files
codingmachines-swarm prompts/TRACK2A.md prompts/TRACK2B.md prompts/TRACK3A.md

# Or manually: spawn VMs then SSH to deliver prompts
codingmachines run --name "task1" --no-tailscale
codingmachines run --name "task2" --no-tailscale
codingmachines-ssh 10.0.100.2  # deliver prompt to task1
codingmachines-ssh 10.0.100.3  # deliver prompt to task2

# Monitor
codingmachines list
```

### Stop and Clean Up
```bash
# Stop a VM (workspace preserved in ZFS snapshot)
codingmachines stop <task-id>

# List all (including stopped)
codingmachines list --status stopped

# Delete a task completely
codingmachines destroy --force <task-id>
```

## Secrets Management

Secrets are stored on the host VM at `/etc/stockyard/secrets/.env` and injected into every micro-VM at boot. Current secrets:

- `ANTHROPIC_API_KEY` — Claude API access
- `GITHUB_TOKEN` — GitHub repo access
- `GOOGLE_CLOUD_PROJECT` — GCP project ID
- `GCP_REGION` — Default region

To update secrets (admin only):
```bash
gcloud compute ssh codingmachines --zone=us-central1-a --tunnel-through-iap \
  --command="sudo nano /etc/stockyard/secrets/.env"
```

## Cost

| Component | Cost |
|-----------|------|
| Host VM (n2-standard-8 Spot) | ~$0.05/hr when running |
| Static IP | $0 when attached to running VM, $0.01/hr when stopped |
| 200GB disk | ~$20/month |
| Auto-stop after 30 min idle | Saves ~80% of compute cost |
| **Typical monthly (8hr/day, 22 days)** | **~$10-15/month** |

## Troubleshooting

### "connection error: dial unix /var/run/stockyard/stockyard.sock"
Your CLI is trying to connect to a local daemon. Make sure `CODINGMACHINES_URL` is set:
```bash
echo $CODINGMACHINES_URL
# Should show: grpc://codingmachines.mcsquared.cloud:65433
```

### "connection refused" on port 65433
The host VM is probably stopped. Restart it:
```bash
codingmachines-start
# Or manually: gcloud compute instances start codingmachines --zone=us-central1-a
```

### DNS not resolving
Verify the DNS record is set up correctly:
```bash
dig codingmachines.mcsquared.cloud +short
# Should show: 34.121.124.99
```

### Host VM not starting
GCP Spot capacity might be exhausted. Wait a few minutes and retry, or check:
```bash
gcloud compute instances describe codingmachines --zone=us-central1-a --format='value(status,scheduling.provisioningModel)'
```

---

## Admin Setup (One-time, done by cloudops)

### Create the Host VM
```bash
gcloud compute networks create stockyard-net --subnet-mode=auto
gcloud compute firewall-rules create stockyard-ssh --network=stockyard-net --allow=tcp:22 --target-tags=stockyard
gcloud compute firewall-rules create stockyard-iap --network=stockyard-net --allow=tcp:22 --source-ranges=35.235.240.0/20 --target-tags=stockyard
gcloud compute firewall-rules create stockyard-grpc --network=stockyard-net --allow=tcp:65433 --target-tags=stockyard

gcloud compute addresses create stockyard-ip --region=us-central1

gcloud compute instances create codingmachines \
  --zone=us-central1-a \
  --machine-type=n2-standard-8 \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --maintenance-policy=TERMINATE \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=200GB \
  --boot-disk-type=pd-balanced \
  --network=stockyard-net \
  --enable-nested-virtualization \
  --metadata=enable-oslogin=TRUE \
  --tags=stockyard \
  --scopes=cloud-platform

# Assign static IP (stop/start required)
STATIC_IP=$(gcloud compute addresses describe stockyard-ip --region=us-central1 --format='value(address)')
gcloud compute instances stop codingmachines --zone=us-central1-a
gcloud compute instances delete-access-config codingmachines --zone=us-central1-a --access-config-name="external-nat"
gcloud compute instances add-access-config codingmachines --zone=us-central1-a --address=$STATIC_IP
gcloud compute instances start codingmachines --zone=us-central1-a
```

### Install Stockyard on Host VM
```bash
gcloud compute ssh codingmachines --zone=us-central1-a --tunnel-through-iap --command='
set -e

# ZFS
sudo apt-get update -qq && sudo apt-get install -y -qq zfsutils-linux git make wget
sudo modprobe zfs
sudo truncate -s 100G /var/lib/stockyard-pool.img
sudo zpool create tank /var/lib/stockyard-pool.img
sudo zfs create tank/stockyard
sudo zfs create tank/stockyard/workspaces
sudo zfs create tank/stockyard/images
sudo zfs create tank/stockyard/vms
sudo zfs set compression=lz4 tank/stockyard

# Go
wget -q https://go.dev/dl/go1.24.1.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.24.1.linux-amd64.tar.gz

# Firecracker
wget -q https://github.com/firecracker-microvm/firecracker/releases/download/v1.10.1/firecracker-v1.10.1-x86_64.tgz
tar xf firecracker-v1.10.1-x86_64.tgz
sudo install -m 0755 release-v1.10.1-x86_64/firecracker-v1.10.1-x86_64 /usr/local/bin/firecracker
sudo install -m 0755 release-v1.10.1-x86_64/jailer-v1.10.1-x86_64 /usr/local/bin/jailer

# Stockyard
cd /tmp && git clone https://github.com/prime-radiant-inc/stockyard.git
cd stockyard && export PATH=$PATH:/usr/local/go/bin
CGO_ENABLED=1 go build -o bin/stockyardd ./cmd/stockyardd
CGO_ENABLED=1 go build -o bin/stockyard ./cmd/stockyard
sudo install -m 0755 bin/stockyardd /usr/local/bin/
sudo install -m 0755 bin/stockyard /usr/local/bin/

# VM Image
cd vm-image && sudo apt-get install -y -qq docker.io && sudo systemctl start docker
sudo ./build.sh && sudo ./convert-to-rootfs.sh
sudo zfs create tank/stockyard/images/rootfs
sudo cp output/rootfs.ext4 /tank/stockyard/images/rootfs/
sudo zfs snapshot tank/stockyard/images/rootfs@base
sudo cp output/vmlinux.bin /var/lib/stockyard/

# Initialize
stockyard init --instance mcsquared-dev

# Fix secrets provider (dir instead of 1password)
sudo python3 -c "
import json
with open(\"/etc/stockyard/config.json\") as f: cfg = json.load(f)
cfg[\"secrets\"][\"provider\"] = \"dir\"
cfg[\"secrets\"][\"dir\"] = \"/etc/stockyard/secrets\"
with open(\"/etc/stockyard/config.json\", \"w\") as f: json.dump(cfg, f, indent=2)
"

# Secrets
sudo mkdir -p /etc/stockyard/secrets
sudo tee /etc/stockyard/secrets/.env > /dev/null << SECRETS
ANTHROPIC_API_KEY=<your-key>
GITHUB_TOKEN=<your-token>
GOOGLE_CLOUD_PROJECT=sales-demos-485118
GCP_REGION=us-central1
SUPABASE_URL=<your-supabase-url>
SUPABASE_ANON_KEY=<your-supabase-key>
GCS_BUCKET=<your-gcs-bucket>
SECRETS
sudo chmod 600 /etc/stockyard/secrets/.env

# SSH keys for VM access (since vsock is broken on GCP nested virt)
sudo mkdir -p /etc/stockyard/ssh
sudo ssh-keygen -t ed25519 -f /etc/stockyard/ssh/vm_key -N "" -C "codingmachines-to-vm"
sudo chmod 600 /etc/stockyard/ssh/vm_key
sudo chmod 644 /etc/stockyard/ssh/vm_key.pub

# Inject SSH key into rootfs
sudo mkdir -p /tmp/rootfs-mount
sudo mount /tank/stockyard/images/rootfs/rootfs.ext4 /tmp/rootfs-mount
sudo mkdir -p /tmp/rootfs-mount/home/mooby/.ssh
sudo cp /etc/stockyard/ssh/vm_key.pub /tmp/rootfs-mount/home/mooby/.ssh/authorized_keys
sudo chown -R 1001:1001 /tmp/rootfs-mount/home/mooby/.ssh
sudo chmod 700 /tmp/rootfs-mount/home/mooby/.ssh
sudo chmod 600 /tmp/rootfs-mount/home/mooby/.ssh/authorized_keys
sudo umount /tmp/rootfs-mount
sudo zfs destroy tank/stockyard/images/rootfs@base
sudo zfs snapshot tank/stockyard/images/rootfs@base

# Network bridge + NAT (10.0.100.0/24 subnet)
sudo ip link add name flbr0 type bridge
sudo ip addr add 10.0.100.1/24 dev flbr0
sudo ip link set flbr0 up
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo iptables -t nat -A POSTROUTING -s 10.0.100.0/24 -o ens4 -j MASQUERADE
sudo iptables -A FORWARD -i flbr0 -o ens4 -j ACCEPT
sudo iptables -A FORWARD -i ens4 -o flbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Systemd: network (bridge + NAT, survives reboots)
sudo tee /etc/systemd/system/stockyard-network.service > /dev/null << "NETEOF"
[Unit]
Description=Stockyard VM Network (bridge + NAT)
Before=stockyard.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "ip link add name flbr0 type bridge 2>/dev/null || true; ip link set flbr0 up; ip addr replace 10.0.100.1/24 dev flbr0; iptables -t nat -C POSTROUTING -s 10.0.100.0/24 -o ens4 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.0.100.0/24 -o ens4 -j MASQUERADE; iptables -C FORWARD -i flbr0 -o ens4 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i flbr0 -o ens4 -j ACCEPT; iptables -C FORWARD -i ens4 -o flbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i ens4 -o flbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT"

[Install]
WantedBy=multi-user.target
NETEOF
sudo systemctl daemon-reload
sudo systemctl enable stockyard-network

# Systemd: stockyard daemon
sudo tee /etc/systemd/system/stockyard.service > /dev/null << "SVCEOF"
[Unit]
Description=Stockyard Daemon
After=network.target zfs-mount.service stockyard-network.service
Wants=zfs-mount.service

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p /var/run/stockyard
ExecStart=/usr/local/bin/stockyardd --config /etc/stockyard/config.json
Restart=on-failure
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SVCEOF
sudo systemctl daemon-reload
sudo systemctl enable stockyard
sudo systemctl start stockyard

# Idle auto-shutdown (30 min)
sudo tee /usr/local/bin/stockyard-idle-shutdown.sh > /dev/null << "SCRIPT"
#!/bin/bash
IDLE_FILE=/tmp/stockyard-idle-since
TASKS=$(stockyard list 2>/dev/null | grep -c running || echo 0)
if [ "$TASKS" -gt 0 ]; then rm -f $IDLE_FILE; exit 0; fi
if [ ! -f $IDLE_FILE ]; then date +%s > $IDLE_FILE; exit 0; fi
IDLE_SINCE=$(cat $IDLE_FILE); NOW=$(date +%s); IDLE_SECONDS=$((NOW - IDLE_SINCE))
if [ $IDLE_SECONDS -gt 1800 ]; then logger "Stockyard idle shutdown"; sudo shutdown -h now; fi
SCRIPT
sudo chmod +x /usr/local/bin/stockyard-idle-shutdown.sh
echo "*/5 * * * * root /usr/local/bin/stockyard-idle-shutdown.sh" | sudo tee /etc/cron.d/stockyard-idle

# Start daemon
sudo nohup stockyardd > /var/log/stockyardd.log 2>&1 &
'
```

### GCP Org Policy Required
Nested virtualization must be enabled at org level:
```
Constraint: compute.disableNestedVirtualization
Must be: NOT enforced
```

If enforced, admin must remove it:
```bash
gcloud resource-manager org-policies disable-enforce \
  compute.disableNestedVirtualization --project=sales-demos-485118
```

### DNS Setup (Cloudflare)

The domain `mcsquared.cloud` is managed via Cloudflare. Add an A record:

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `codingmachines` | `34.121.124.99` | DNS only (no proxy) | Auto |

**Important**: Set proxy to "DNS only" (gray cloud), not "Proxied" (orange cloud).
gRPC traffic on port 65433 cannot pass through Cloudflare's HTTP proxy.

To add via Cloudflare API:
```bash
# Get zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=mcsquared.cloud" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result[0].id')

# Create A record
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "codingmachines",
    "content": "34.121.124.99",
    "ttl": 1,
    "proxied": false
  }'
```

For additional hosts (per-developer or per-workload), add more A records:
- `codingmachines-dev.mcsquared.cloud` → dev host IP
- `codingmachines-prod.mcsquared.cloud` → prod host IP
- `codingmachines-<name>.mcsquared.cloud` → per-developer host IP

### Multiple Hosts (Scaling)

For teams needing isolated environments, provision additional hosts:

```bash
# Create a new host with unique name
gcloud compute instances create codingmachines-dev \
  --zone=us-central1-a \
  --machine-type=n2-standard-8 \
  --provisioning-model=SPOT \
  ...  # (same flags as primary host)

# Reserve a new static IP
gcloud compute addresses create codingmachines-dev-ip --region=us-central1

# Add DNS: codingmachines-dev.mcsquared.cloud → new IP
```

Developers switch hosts by changing their env:
```bash
export CODINGMACHINES_URL=grpc://codingmachines-dev.mcsquared.cloud:65433
export STOCKYARD_URL=$CODINGMACHINES_URL
```
