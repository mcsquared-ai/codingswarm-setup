# SSH Access to CodingMachines Micro-VMs

> Since Firecracker vsock is not available on GCP nested virtualization,
> we use SSH over the TAP bridge network to access micro-VMs.

## Architecture

```
Your Mac/PC
  └── gcloud IAP tunnel (encrypted)
       └── codingmachines.mcsquared.cloud (10.0.100.1)
            └── SSH over bridge (flbr0)
                 ├── micro-VM 1 (10.0.100.2)
                 ├── micro-VM 2 (10.0.100.3)
                 └── micro-VM N (10.0.100.N+1)
```

## One-Time Setup (per developer)

### 1. Copy the VM SSH key to your machine

```bash
gcloud compute scp stockyard-host:/etc/stockyard/ssh/vm_key ~/.ssh/codingmachines_vm_key \
  --project=sales-demos-485118 --zone=us-central1-a --tunnel-through-iap

chmod 600 ~/.ssh/codingmachines_vm_key
```

### 2. Add SSH config

Add to `~/.ssh/config`:

```ssh-config
# CodingMachines host via IAP tunnel
Host stockyard-host
    HostName codingmachines.mcsquared.cloud
    User pankaj_shroff_mcsquared_ai
    ProxyCommand gcloud compute start-iap-tunnel stockyard-host %p --project=sales-demos-485118 --zone=us-central1-a --listen-on-stdin 2>/dev/null

# CodingMachines micro-VMs via host jump
Host vm-*
    User mooby
    ProxyJump stockyard-host
    IdentityFile ~/.ssh/codingmachines_vm_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
```

> **Note**: Replace `pankaj_shroff_mcsquared_ai` with your OS Login username
> (run `gcloud compute os-login describe-profile --format='value(posixAccounts[0].username)'`).

## Usage

### Quick SSH (one-liner, no config needed)

```bash
# SSH into a VM at 10.0.100.2
CLOUDSDK_ACTIVE_CONFIG_NAME=default \
gcloud compute ssh stockyard-host \
  --project=sales-demos-485118 --zone=us-central1-a --tunnel-through-iap \
  -- -t ssh -i ~/.ssh/stockyard_vm_key mooby@10.0.100.2
```

### With SSH config (after setup above)

```bash
# Jump through host to VM
ssh -J stockyard-host mooby@10.0.100.2
```

### Run a command without interactive shell

```bash
# From host (if already SSH'd in)
ssh -i ~/.ssh/vm_key mooby@10.0.100.2 'uname -a'

# From your Mac (two-hop)
CLOUDSDK_ACTIVE_CONFIG_NAME=default \
gcloud compute ssh stockyard-host \
  --project=sales-demos-485118 --zone=us-central1-a --tunnel-through-iap \
  --command="ssh mooby@10.0.100.2 'uname -a'"
```

## Finding VM IPs

VMs get DHCP addresses starting at `10.0.100.2`, assigned in creation order.

```bash
# From your Mac (via CodingMachines CLI)
codingmachines list

# Check DHCP leases (from host)
gcloud compute ssh stockyard-host ... --command="cat /var/lib/stockyard/data/dnsmasq.leases"
```

The DHCP lease file shows: `<timestamp> <mac> <ip> <hostname> *`

Hostnames follow the pattern `stockyard-<task-id>`, e.g., `stockyard-7ad72caa`.

## VM User

All VMs use the `mooby` user (UID 1001). This user has:
- Passwordless sudo
- SSH pubkey auth (key baked into rootfs)
- Home directory at `/home/mooby`
- Secrets injected as environment variables from `/etc/stockyard/secrets/.env`

## Sending Coding Prompts via SSH

Since `codingmachines exec` / `stockyard exec` relies on vsock (broken on GCP), deliver prompts via SSH:

```bash
# From the host VM
VM_IP=10.0.100.2

# Clone repo and run claude-code
ssh -i ~/.ssh/vm_key mooby@$VM_IP 'bash -ls' <<'PROMPT'
cd /home/mooby
git clone https://github.com/mcsquared-ai/mc2-IgAN-LaunchToolkit
cd mc2-IgAN-LaunchToolkit
claude-code -p "$(cat prompts/TRACK2A_NPI_HCP_REGISTRY.md)"
PROMPT
```

### Launch a coding swarm (3 parallel agents)

```bash
# Launch 3 VMs
ID1=$(stockyard run --name track2a --no-tailscale 2>&1 | grep 'Task created' | awk '{print $3}')
ID2=$(stockyard run --name track2b --no-tailscale 2>&1 | grep 'Task created' | awk '{print $3}')
ID3=$(stockyard run --name track3a --no-tailscale 2>&1 | grep 'Task created' | awk '{print $3}')

sleep 10  # wait for DHCP

# Deliver prompts via SSH (background each)
for i in 2 3 4; do
  ssh -i ~/.ssh/vm_key mooby@10.0.100.$i 'bash -ls' <<PROMPT &
    cd /home/mooby
    git clone https://github.com/mcsquared-ai/mc2-IgAN-LaunchToolkit
    cd mc2-IgAN-LaunchToolkit
    # prompt varies per VM — use task name or index to pick
    claude-code -p "\$(cat prompts/TRACK2A_NPI_HCP_REGISTRY.md)"
PROMPT
done

wait
echo "All agents complete."
```

## Troubleshooting

### "Permission denied (publickey)"

The SSH key wasn't baked into the rootfs, or you're using the wrong key.

```bash
# Verify from host
ssh -v -i ~/.ssh/vm_key mooby@10.0.100.2

# Re-inject key into rootfs (requires stopping all VMs)
sudo mount /tank/stockyard/images/rootfs/rootfs.ext4 /tmp/rootfs-mount
sudo cp /etc/stockyard/ssh/vm_key.pub /tmp/rootfs-mount/home/mooby/.ssh/authorized_keys
sudo chown 1001:1001 /tmp/rootfs-mount/home/mooby/.ssh/authorized_keys
sudo chmod 600 /tmp/rootfs-mount/home/mooby/.ssh/authorized_keys
sudo umount /tmp/rootfs-mount
sudo zfs destroy tank/stockyard/images/rootfs@base
sudo zfs snapshot tank/stockyard/images/rootfs@base
```

### VM has no internet

Check NAT and forwarding on the host:

```bash
# Verify NAT rule exists
sudo iptables -t nat -L POSTROUTING -n | grep 10.0.100

# Verify forwarding
sysctl net.ipv4.ip_forward
sudo iptables -L FORWARD -n | grep flbr0

# Test from inside VM
ssh -i ~/.ssh/vm_key mooby@10.0.100.2 'curl -s https://api.anthropic.com'
```

### Can't find VM IP

```bash
# List all leases
cat /var/lib/stockyard/data/dnsmasq.leases

# Or ping-scan the subnet
for i in $(seq 2 10); do ping -c1 -W1 10.0.100.$i 2>/dev/null && echo "10.0.100.$i UP"; done
```

## Why Not vsock?

Firecracker uses virtio-vsock (`/dev/vsock`) for host↔VM communication.
GCP nested virtualization does not expose `/dev/vsock` to the guest,
so the Firecracker vsock proxy cannot connect. The `stockyard exec`
command fails with `read CONNECT response: EOF`.

SSH over the TAP bridge network (`flbr0`) bypasses this limitation entirely.
