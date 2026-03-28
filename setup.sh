#!/usr/bin/env bash
# ============================================================================
# mcsquared.ai — Developer Workstation Setup + Stockyard Coding Swarm
#
# Run: curl -fsSL https://raw.githubusercontent.com/mcsquared-ai/mc2-IgAN-LaunchToolkit/main/scripts/stockyard-dev-setup.sh | bash
# Or:  bash scripts/stockyard-dev-setup.sh
#
# Supports: macOS (arm64/amd64), Linux (x86_64), Windows (WSL2)
# ============================================================================

set -e

# Config
STOCKYARD_HOST="34.121.124.99"
STOCKYARD_PORT="65433"
STOCKYARD_URL="grpc://${STOCKYARD_HOST}:${STOCKYARD_PORT}"
GCP_PROJECT="sales-demos-485118"
GCP_ZONE="us-central1-a"
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

# ── Build Stockyard CLI ──────────────────────────────────────────────

build_stockyard_cli() {
    info "Building Stockyard CLI for $PLATFORM/$GOARCH..."

    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"

    git clone --depth 1 "$STOCKYARD_REPO" stockyard 2>/dev/null
    cd stockyard

    GOOS=$PLATFORM GOARCH=$GOARCH go build -o stockyard-cli ./cmd/stockyard

    mkdir -p "$HOME/.local/bin"
    cp stockyard-cli "$HOME/.local/bin/stockyard"
    chmod +x "$HOME/.local/bin/stockyard"

    # Clean up
    cd /
    rm -rf "$TMPDIR"

    log "Stockyard CLI installed: $HOME/.local/bin/stockyard"
    "$HOME/.local/bin/stockyard" version
}

# ── Configure environment ────────────────────────────────────────────

configure_environment() {
    info "Configuring environment..."

    # Stockyard config
    mkdir -p "$HOME/.stockyard"
    cat > "$HOME/.stockyard/env.sh" << EOF
# mcsquared.ai Stockyard Coding Swarm
export STOCKYARD_URL=${STOCKYARD_URL}
export PATH=\$PATH:\$HOME/.local/bin
EOF

    # Add to shell profile if not already there
    if ! grep -q "stockyard/env.sh" "$SHELL_RC" 2>/dev/null; then
        echo '' >> "$SHELL_RC"
        echo '# mcsquared.ai Stockyard' >> "$SHELL_RC"
        echo 'source ~/.stockyard/env.sh' >> "$SHELL_RC"
        log "Added to $SHELL_RC"
    else
        warn "Already in $SHELL_RC"
    fi

    # Source for current session
    export STOCKYARD_URL="${STOCKYARD_URL}"
    export PATH="$PATH:$HOME/.local/bin"

    log "STOCKYARD_URL=$STOCKYARD_URL"
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

# ── Verify Stockyard connection ──────────────────────────────────────

verify_connection() {
    info "Testing Stockyard connection to $STOCKYARD_HOST..."

    if "$HOME/.local/bin/stockyard" list &>/dev/null; then
        log "Stockyard daemon: connected"
    else
        warn "Cannot reach Stockyard daemon at $STOCKYARD_URL"
        warn "The host VM may be stopped. To start it:"
        echo ""
        echo "  gcloud compute instances start stockyard-host --zone=$GCP_ZONE --project=$GCP_PROJECT"
        echo "  # Wait 30 seconds, then retry: stockyard list"
        echo ""
    fi
}

# ── Helper scripts ───────────────────────────────────────────────────

create_helper_scripts() {
    info "Creating helper scripts..."

    # stockyard-start: Start the host VM
    cat > "$HOME/.local/bin/stockyard-start" << 'EOF'
#!/bin/bash
echo "Starting Stockyard host VM..."
gcloud compute instances start stockyard-host --zone=us-central1-a --project=sales-demos-485118
echo "Waiting for boot..."
sleep 25
echo "Checking connection..."
stockyard list && echo "Ready!" || echo "Daemon may need manual restart — see docs"
EOF
    chmod +x "$HOME/.local/bin/stockyard-start"

    # stockyard-stop: Stop the host VM
    cat > "$HOME/.local/bin/stockyard-stop" << 'EOF'
#!/bin/bash
echo "Stopping Stockyard host VM..."
gcloud compute instances stop stockyard-host --zone=us-central1-a --project=sales-demos-485118
echo "Stopped. No compute charges while stopped."
EOF
    chmod +x "$HOME/.local/bin/stockyard-stop"

    # stockyard-status: Check host VM status
    cat > "$HOME/.local/bin/stockyard-status" << 'EOF'
#!/bin/bash
STATUS=$(gcloud compute instances describe stockyard-host --zone=us-central1-a --project=sales-demos-485118 --format='value(status)' 2>/dev/null)
echo "Host VM: $STATUS"
if [ "$STATUS" = "RUNNING" ]; then
    stockyard list 2>/dev/null || echo "Daemon not responding"
fi
EOF
    chmod +x "$HOME/.local/bin/stockyard-status"

    # stockyard-swarm: Run multiple agents
    cat > "$HOME/.local/bin/stockyard-swarm" << 'SWARMEOF'
#!/bin/bash
# Usage: stockyard-swarm task1.md task2.md task3.md
# Each .md file contains a prompt for one agent
if [ $# -eq 0 ]; then
    echo "Usage: stockyard-swarm <prompt1.md> [prompt2.md] [prompt3.md] ..."
    echo "Each file contains a Claude Code prompt for one micro-VM agent."
    exit 1
fi

PIDS=()
for PROMPT_FILE in "$@"; do
    NAME=$(basename "$PROMPT_FILE" .md)
    PROMPT=$(cat "$PROMPT_FILE")
    echo "Spawning agent: $NAME"
    TASK_ID=$(stockyard run --name "$NAME" --no-tailscale 2>&1 | grep "Task created:" | awk '{print $3}')
    if [ -n "$TASK_ID" ]; then
        echo "  Task $TASK_ID created for $NAME"
        stockyard exec "$TASK_ID" --no-stop-on-failure -- claude-code -p "$PROMPT" &
        PIDS+=($!)
    else
        echo "  Failed to create task for $NAME"
    fi
done

echo ""
echo "Swarm launched: ${#PIDS[@]} agents"
echo "Monitor: stockyard list"
SWARMEOF
    chmod +x "$HOME/.local/bin/stockyard-swarm"

    log "Helper scripts created:"
    echo "  stockyard-start   — Start the host VM"
    echo "  stockyard-stop    — Stop the host VM (save money)"
    echo "  stockyard-status  — Check host VM + daemon status"
    echo "  stockyard-swarm   — Launch multiple agents from prompt files"
}

# ── Summary ──────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  mcsquared.ai Developer Setup Complete${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Platform:     $PLATFORM/$GOARCH"
    echo "  Stockyard:    $HOME/.local/bin/stockyard"
    echo "  Host VM:      $STOCKYARD_HOST (GCP Spot, auto-stops after 30min)"
    echo "  Config:       $HOME/.stockyard/env.sh"
    echo ""
    echo -e "  ${GREEN}Quick Start:${NC}"
    echo "    stockyard-status           # Check if host VM is running"
    echo "    stockyard-start            # Start host VM if stopped"
    echo "    stockyard list             # List running micro-VMs"
    echo "    stockyard run --name test  # Spawn a micro-VM"
    echo "    stockyard-swarm a.md b.md  # Launch coding swarm"
    echo ""
    echo -e "  ${YELLOW}Note: Open a new terminal for PATH changes to take effect${NC}"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${CYAN}mcsquared.ai Developer Workstation Setup${NC}"
    echo -e "${CYAN}Stockyard Coding Agent Farm${NC}"
    echo ""

    detect_platform
    install_prerequisites
    build_stockyard_cli
    configure_environment
    authenticate
    create_helper_scripts
    verify_connection
    print_summary
}

main "$@"
