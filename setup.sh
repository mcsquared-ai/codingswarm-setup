#!/usr/bin/env bash
# ============================================================================
# mcsquared.ai — Developer Workstation Setup + CodingMachines Agent Swarm
#
# Run: curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/codingswarm-setup/main/setup.sh | bash
# Or:  bash setup.sh
#
# Supports: macOS (arm64/amd64), Linux (x86_64), Windows (WSL2)
# ============================================================================

set -e

# Config
CM_HOST="codingmachines.mcsquared.cloud"
CM_PORT="65433"
CM_URL="grpc://${CM_HOST}:${CM_PORT}"
GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
GCP_VM_NAME="codingmachines"
STOCKYARD_REPO="https://github.com/prime-radiant-inc/stockyard.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[→]${NC} $1"; }

# ── Detect platform ──────────────────────────────────────────────────

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Darwin)
            PLATFORM="darwin"
            SHELL_RC="$HOME/.zshrc"
            PKG_MANAGER="brew"
            ;;
        Linux)
            PLATFORM="linux"
            if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
                PLATFORM="wsl"
            fi
            SHELL_RC="$HOME/.bashrc"
            if [ -f "$HOME/.zshrc" ]; then SHELL_RC="$HOME/.zshrc"; fi
            PKG_MANAGER="apt"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            err "Native Windows not supported. Please use WSL2."
            err "Install WSL2: wsl --install"
            exit 1
            ;;
        *)
            err "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  GOARCH="amd64" ;;
        arm64|aarch64) GOARCH="arm64" ;;
        *)
            err "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    log "Platform: $PLATFORM/$GOARCH (shell: $SHELL_RC)"
}

# ── Install prerequisites ────────────────────────────────────────────

install_prerequisites() {
    info "Checking prerequisites..."

    # Git
    if command -v git &>/dev/null; then
        log "Git: $(git --version | head -1)"
    else
        info "Installing git..."
        case "$PKG_MANAGER" in
            brew) brew install git ;;
            apt)  sudo apt-get update -qq && sudo apt-get install -y -qq git ;;
        esac
        log "Git installed"
    fi

    # Go
    if command -v go &>/dev/null; then
        log "Go: $(go version | awk '{print $3}')"
    else
        info "Installing Go..."
        case "$PKG_MANAGER" in
            brew) brew install go ;;
            apt)
                GO_VERSION="1.24.1"
                wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" -O /tmp/go.tar.gz
                sudo rm -rf /usr/local/go
                sudo tar -C /usr/local -xzf /tmp/go.tar.gz
                export PATH=$PATH:/usr/local/go/bin
                ;;
        esac
        log "Go installed: $(go version | awk '{print $3}')"
    fi

    # Google Cloud SDK
    if command -v gcloud &>/dev/null; then
        log "gcloud: $(gcloud --version 2>/dev/null | head -1)"
    else
        info "Installing Google Cloud SDK..."
        case "$PKG_MANAGER" in
            brew) brew install --cask google-cloud-sdk ;;
            apt)
                echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
                    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
                curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
                    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
                sudo apt-get update -qq && sudo apt-get install -y -qq google-cloud-cli
                ;;
        esac
        log "gcloud installed"
    fi

    # GitHub CLI
    if command -v gh &>/dev/null; then
        log "GitHub CLI: $(gh --version | head -1)"
    else
        info "Installing GitHub CLI..."
        case "$PKG_MANAGER" in
            brew) brew install gh ;;
            apt)
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
                    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
                    sudo tee /etc/apt/sources.list.d/github-cli.list
                sudo apt-get update -qq && sudo apt-get install -y -qq gh
                ;;
        esac
        log "GitHub CLI installed"
    fi

    # Python + uv
    if command -v python3 &>/dev/null; then
        log "Python: $(python3 --version)"
    else
        info "Installing Python..."
        case "$PKG_MANAGER" in
            brew) brew install python@3.12 ;;
            apt)  sudo apt-get install -y -qq python3 python3-pip ;;
        esac
        log "Python installed"
    fi

    if command -v uv &>/dev/null; then
        log "uv: $(uv --version)"
    else
        info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        log "uv installed"
    fi

    # Node.js
    if command -v node &>/dev/null; then
        log "Node: $(node --version)"
    else
        info "Installing Node.js..."
        case "$PKG_MANAGER" in
            brew) brew install node@20 ;;
            apt)
                curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
                sudo apt-get install -y -qq nodejs
                ;;
        esac
        log "Node installed"
    fi
}

# ── Build CodingMachines CLI (wraps Stockyard) ────────────────────────

build_cli() {
    info "Building CodingMachines CLI for $PLATFORM/$GOARCH..."

    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"

    git clone --depth 1 "$STOCKYARD_REPO" stockyard 2>/dev/null
    cd stockyard

    GOOS=$PLATFORM GOARCH=$GOARCH go build -o stockyard-cli ./cmd/stockyard

    mkdir -p "$HOME/.local/bin"

    # Install the underlying binary
    cp stockyard-cli "$HOME/.local/bin/stockyard"
    chmod +x "$HOME/.local/bin/stockyard"

    # Create the branded wrapper
    cat > "$HOME/.local/bin/codingmachines" << 'WRAPPER'
#!/bin/bash
# CodingMachines — mcsquared.ai coding agent orchestrator
# Wraps Stockyard (https://github.com/prime-radiant-inc/stockyard)
#
# Auto-injects --no-tailscale for "run" commands since CodingMachines
# uses SSH over bridge network instead of Tailscale for VM access.
if [ "${1:-}" = "run" ]; then
    shift
    exec stockyard run --no-tailscale "$@"
else
    exec stockyard "$@"
fi
WRAPPER
    chmod +x "$HOME/.local/bin/codingmachines"

    # Clean up
    cd /
    rm -rf "$TMPDIR"

    log "CodingMachines CLI installed: $HOME/.local/bin/codingmachines"
    "$HOME/.local/bin/codingmachines" version
}

# ── Configure environment ────────────────────────────────────────────

configure_environment() {
    info "Configuring environment..."

    # CodingMachines config
    mkdir -p "$HOME/.codingmachines"
    cat > "$HOME/.codingmachines/env.sh" << EOF
# mcsquared.ai CodingMachines — Coding Agent Swarm
export CODINGMACHINES_URL=${CM_URL}
export CODINGMACHINES_HOST=${CM_HOST}
export STOCKYARD_URL=\$CODINGMACHINES_URL  # required by underlying Stockyard binary
export PATH=\$PATH:\$HOME/.local/bin
EOF

    # Migrate from old stockyard config if present
    if [ -f "$HOME/.stockyard/env.sh" ]; then
        warn "Found old ~/.stockyard/env.sh — migrating to ~/.codingmachines/env.sh"
    fi

    # Add to shell profile if not already there
    if ! grep -q "codingmachines/env.sh" "$SHELL_RC" 2>/dev/null; then
        # Remove old stockyard source line if present
        if grep -q "stockyard/env.sh" "$SHELL_RC" 2>/dev/null; then
            sed -i.bak '/stockyard\/env.sh/d' "$SHELL_RC"
            sed -i.bak '/mcsquared.ai Stockyard/d' "$SHELL_RC"
            warn "Removed old Stockyard config from $SHELL_RC"
        fi
        echo '' >> "$SHELL_RC"
        echo '# mcsquared.ai CodingMachines' >> "$SHELL_RC"
        echo 'source ~/.codingmachines/env.sh' >> "$SHELL_RC"
        log "Added to $SHELL_RC"
    else
        warn "Already in $SHELL_RC"
    fi

    # Source for current session
    export CODINGMACHINES_URL="${CM_URL}"
    export STOCKYARD_URL="${CM_URL}"
    export PATH="$PATH:$HOME/.local/bin"

    log "CODINGMACHINES_URL=$CM_URL"
}

# ── Authenticate ─────────────────────────────────────────────────────

authenticate() {
    info "Checking authentication..."

    # GCP
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
        ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
        log "GCP: $ACCOUNT"
    else
        warn "GCP not authenticated. Run: gcloud auth login"
    fi

    # GitHub
    if gh auth status &>/dev/null; then
        GH_USER=$(gh api user --jq .login 2>/dev/null || echo "authenticated")
        log "GitHub: $GH_USER"
    else
        warn "GitHub not authenticated. Run: gh auth login"
    fi
}

# ── Verify connection ───────────────────────────────────────────────

verify_connection() {
    info "Testing CodingMachines connection to $CM_HOST..."

    if "$HOME/.local/bin/codingmachines" list &>/dev/null; then
        log "CodingMachines daemon: connected"
    else
        warn "Cannot reach daemon at $CM_URL"
        warn "The host VM may be stopped. To start it:"
        echo ""
        echo "  codingmachines-start"
        echo ""
    fi
}

# ── Helper scripts ───────────────────────────────────────────────────

create_helper_scripts() {
    info "Creating helper scripts..."

    # codingmachines-start: Start the host VM
    cat > "$HOME/.local/bin/codingmachines-start" << 'EOF'
#!/bin/bash
GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
GCP_VM="codingmachines"
echo "Starting CodingMachines host VM..."
gcloud compute instances start "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT"
echo "Waiting for boot..."
sleep 25
echo "Checking connection..."
codingmachines list && echo "Ready!" || echo "Daemon may still be starting — retry in 10s"
EOF
    chmod +x "$HOME/.local/bin/codingmachines-start"

    # codingmachines-stop: Stop the host VM
    cat > "$HOME/.local/bin/codingmachines-stop" << 'EOF'
#!/bin/bash
GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
GCP_VM="codingmachines"
echo "Stopping CodingMachines host VM..."
gcloud compute instances stop "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT"
echo "Stopped. No compute charges while stopped."
EOF
    chmod +x "$HOME/.local/bin/codingmachines-stop"

    # codingmachines-status: Check host VM status
    cat > "$HOME/.local/bin/codingmachines-status" << 'EOF'
#!/bin/bash
GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
GCP_VM="codingmachines"
STATUS=$(gcloud compute instances describe "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT" --format='value(status)' 2>/dev/null)
echo "Host VM: $STATUS"
if [ "$STATUS" = "RUNNING" ]; then
    codingmachines list 2>/dev/null || echo "Daemon not responding"
fi
EOF
    chmod +x "$HOME/.local/bin/codingmachines-status"

    # codingmachines-ssh: SSH into a micro-VM
    cat > "$HOME/.local/bin/codingmachines-ssh" << 'EOF'
#!/bin/bash
# Usage: codingmachines-ssh <vm-ip>
# Example: codingmachines-ssh 10.0.100.2
GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
GCP_VM="codingmachines"
VM_IP="${1:?Usage: codingmachines-ssh <vm-ip>}"

if [ -f "$HOME/.ssh/codingmachines_vm_key" ]; then
    # Use ProxyJump if SSH config is set up
    ssh -J codingmachines "mooby@$VM_IP" 2>/dev/null || \
    gcloud compute ssh "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT" --tunnel-through-iap \
        -- -t ssh -i "$HOME/.ssh/codingmachines_vm_key" "mooby@$VM_IP"
else
    gcloud compute ssh "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT" --tunnel-through-iap \
        -- -t ssh -o StrictHostKeyChecking=no "mooby@$VM_IP"
fi
EOF
    chmod +x "$HOME/.local/bin/codingmachines-ssh"

    # codingmachines-swarm: Run multiple agents via SSH
    cat > "$HOME/.local/bin/codingmachines-swarm" << 'SWARMEOF'
#!/bin/bash
# Usage: codingmachines-swarm <prompt1.md> [prompt2.md] [prompt3.md] ...
# Each .md file contains a Claude Code prompt for one micro-VM agent.
set -e

GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
GCP_VM="codingmachines"

if [ $# -eq 0 ]; then
    echo "Usage: codingmachines-swarm <prompt1.md> [prompt2.md] ..."
    echo "Each file contains a Claude Code prompt for one micro-VM agent."
    exit 1
fi

# Collect prompt files and names
PROMPTS=("$@")
TASK_IDS=()
TASK_NAMES=()

echo "Launching ${#PROMPTS[@]} coding agents..."
echo ""

# Phase 1: Create all VMs
for PROMPT_FILE in "${PROMPTS[@]}"; do
    NAME=$(basename "$PROMPT_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    TASK_NAMES+=("$NAME")
    echo -n "  Creating VM: $NAME ... "
    TASK_ID=$(codingmachines run --name "$NAME" 2>&1 | grep "Task created:" | awk '{print $3}')
    if [ -n "$TASK_ID" ]; then
        TASK_IDS+=("$TASK_ID")
        echo "$TASK_ID"
    else
        echo "FAILED"
        TASK_IDS+=("")
    fi
done

echo ""
echo "Waiting for VMs to boot and get IPs..."
sleep 10

# Phase 2: Deliver prompts via SSH through the host
echo ""
echo "Delivering prompts via SSH..."

# Get DHCP leases to map IPs
LEASES=$(gcloud compute ssh "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT" --tunnel-through-iap \
    --command="cat /var/lib/stockyard/data/dnsmasq.leases 2>/dev/null" 2>/dev/null)

for i in "${!PROMPTS[@]}"; do
    PROMPT_FILE="${PROMPTS[$i]}"
    TASK_ID="${TASK_IDS[$i]}"
    NAME="${TASK_NAMES[$i]}"

    [ -z "$TASK_ID" ] && continue

    # Find VM IP from DHCP leases (hostname = stockyard-<task-id>)
    VM_IP=$(echo "$LEASES" | grep "$TASK_ID" | awk '{print $3}')
    if [ -z "$VM_IP" ]; then
        echo "  $NAME ($TASK_ID): no IP found, skipping"
        continue
    fi

    echo "  $NAME ($TASK_ID) @ $VM_IP: delivering prompt..."

    # Read prompt content
    PROMPT_CONTENT=$(cat "$PROMPT_FILE")

    # Deliver via SSH through IAP tunnel (background)
    gcloud compute ssh "$GCP_VM" --zone="$GCP_ZONE" --project="$GCP_PROJECT" --tunnel-through-iap \
        --command="ssh -o StrictHostKeyChecking=no -i ~/.ssh/vm_key mooby@$VM_IP 'cd /home/mooby && claude-code -p \"$(echo "$PROMPT_CONTENT" | sed 's/"/\\"/g')\"'" \
        2>/dev/null &

    echo "  $NAME: agent started (background)"
done

echo ""
echo "Swarm launched: ${#TASK_IDS[@]} agents"
echo ""
echo "Monitor:  codingmachines list"
echo "SSH in:   codingmachines-ssh <vm-ip>"
echo "Status:   codingmachines-status"
SWARMEOF
    chmod +x "$HOME/.local/bin/codingmachines-swarm"

    log "Helper scripts created:"
    echo "  codingmachines              — CLI (list, run, stop, etc.)"
    echo "  codingmachines-start        — Start the host VM"
    echo "  codingmachines-stop         — Stop the host VM (save money)"
    echo "  codingmachines-status       — Check host VM + daemon status"
    echo "  codingmachines-ssh <ip>     — SSH into a micro-VM"
    echo "  codingmachines-swarm        — Launch parallel coding agents"
}

# ── Summary ──────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  mcsquared.ai CodingMachines Setup Complete${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Platform:     $PLATFORM/$GOARCH"
    echo "  CLI:          $HOME/.local/bin/codingmachines"
    echo "  Host:         $CM_HOST (GCP Spot, auto-stops after 30min)"
    echo "  Config:       $HOME/.codingmachines/env.sh"
    echo ""
    echo -e "  ${GREEN}Quick Start:${NC}"
    echo "    codingmachines-status              # Check if host is running"
    echo "    codingmachines-start               # Start host VM if stopped"
    echo "    codingmachines list                # List running micro-VMs"
    echo "    codingmachines run --name my-task  # Spawn a micro-VM"
    echo "    codingmachines-ssh 10.0.100.2      # SSH into a VM"
    echo "    codingmachines-swarm a.md b.md     # Launch coding swarm"
    echo ""
    echo -e "  ${YELLOW}Note: Open a new terminal for PATH changes to take effect${NC}"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${CYAN}mcsquared.ai Developer Workstation Setup${NC}"
    echo -e "${CYAN}CodingMachines — Coding Agent Swarm${NC}"
    echo ""

    detect_platform
    install_prerequisites
    build_cli
    configure_environment
    authenticate
    create_helper_scripts
    verify_connection
    print_summary
}

main "$@"
