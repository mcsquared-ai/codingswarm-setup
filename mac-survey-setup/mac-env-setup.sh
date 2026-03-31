#!/usr/bin/env bash
# =============================================================================
# mac-env-setup.sh
# Idempotent Mac development environment setup for Claude Code
# Enterprise AI Systems of Action | mcsquared.ai
#
# Usage:
#   ./mac-env-setup.sh              # Install Python 3.12.9 only
#   INSTALL_LTS=1 ./mac-env-setup.sh # Also install Python 3.11.9 (LTS)
#
# Safe to re-run — skips steps already complete.
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $1"; }
success() { echo -e "${GREEN}[OK]${RESET}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; }
step()    { echo -e "\n${BOLD}${BLUE}══ $1 ══${RESET}"; }
skip()    { echo -e "${YELLOW}[SKIP]${RESET}  $1 (already installed)"; }

# ── Check macOS ───────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  error "This script is for macOS only."; exit 1
fi

ARCH=$(uname -m)
step "Mac Dev Environment Setup"
info "Architecture : $ARCH"
info "macOS        : $(sw_vers -productVersion)"
echo ""

# ── Config ────────────────────────────────────────────────────────────────────
# Single Python version. 3.12.9 is the latest 3.12.x patch —
# it includes the tcl-tk 9 compatibility fix required on macOS 14+.
PYTHON_VERSION="3.12.9"
INSTALL_LTS="${INSTALL_LTS:-0}"   # Set INSTALL_LTS=1 to also install 3.11.9
PYTHON_VERSION_LTS="3.11.9"

NODE_LTS="20"
ZSHRC="$HOME/.zshrc"
DEV_DIR="$HOME/dev"
ENVS_DIR="$HOME/.envs"

# ── Helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

append_if_missing() {
  local line="$1" file="$2"
  grep -qF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# ═════════════════════════════════════════════════════════════════════════════
step "1 / Xcode Command Line Tools"
# ═════════════════════════════════════════════════════════════════════════════
if xcode-select -p &>/dev/null; then
  skip "Xcode CLT"
else
  info "Installing Xcode Command Line Tools..."
  xcode-select --install
  until xcode-select -p &>/dev/null; do sleep 5; done
  success "Xcode CLT installed"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "2 / Homebrew"
# ═════════════════════════════════════════════════════════════════════════════
if command_exists brew; then
  skip "Homebrew"
  brew update --quiet
else
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ "$ARCH" == "arm64" ]]; then
    append_if_missing 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$ZSHRC"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  success "Homebrew installed"
fi
brew analytics off

# ═════════════════════════════════════════════════════════════════════════════
step "3 / Core CLI Tools"
# ═════════════════════════════════════════════════════════════════════════════
BREW_TOOLS=(
  git gh direnv jq yq tree bat ripgrep fd fzf zoxide tmux wget gnupg
  openssl readline sqlite3 xz zlib tcl-tk httpie libpq starship pyenv nvm
)
for tool in "${BREW_TOOLS[@]}"; do
  if brew list "$tool" &>/dev/null; then skip "$tool"
  else info "Installing $tool..."; brew install "$tool" && success "$tool installed"; fi
done

# ── tcl-tk version guard ──────────────────────────────────────────────────────
# Homebrew tcl-tk@9 breaks Python builds older than 3.12.7.
# Python 3.12.9 handles tcl-tk@9 correctly so no workaround is needed,
# but if tcl-tk@8 is already present we prefer it to keep builds deterministic.
TCL_FLAGS=""
if brew list tcl-tk@8 &>/dev/null; then
  TCL_PREFIX="$(brew --prefix tcl-tk@8)"
  TCL_FLAGS="--with-tcltk-includes='-I${TCL_PREFIX}/include' --with-tcltk-libs='-L${TCL_PREFIX}/lib -ltcl8.6 -ltk8.6'"
  info "tcl-tk@8 found — using it for deterministic Python builds"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "4 / Homebrew Casks"
# ═════════════════════════════════════════════════════════════════════════════
for cask in iterm2 docker claude; do
  if brew list --cask "$cask" &>/dev/null; then skip "$cask"
  else info "Installing $cask..."; brew install --cask "$cask" && success "$cask installed"; fi
done

# ═════════════════════════════════════════════════════════════════════════════
step "5 / pyenv — Python Version Manager"
# ═════════════════════════════════════════════════════════════════════════════
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

PYENV_INIT_BLOCK='
# ── pyenv ────────────────────────────────────────────────────────────────────
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"'

if ! grep -q 'pyenv init' "$ZSHRC" 2>/dev/null; then
  echo "$PYENV_INIT_BLOCK" >> "$ZSHRC"
  eval "$(pyenv init -)"
  success "Added pyenv init to $ZSHRC"
else
  skip "pyenv init block in .zshrc"
  eval "$(pyenv init -)" 2>/dev/null || true
fi

# ── Install Python (one version, 3.12.9) ─────────────────────────────────────
install_python() {
  local ver="$1"
  if pyenv versions --bare 2>/dev/null | grep -q "^${ver}$"; then
    skip "Python $ver"
  else
    info "Installing Python $ver — this takes 3-5 min on first run..."
    CFLAGS="-I$(brew --prefix openssl)/include" \
    LDFLAGS="-L$(brew --prefix openssl)/lib" \
    PYTHON_CONFIGURE_OPTS="${TCL_FLAGS}" \
    pyenv install "$ver"
    success "Python $ver installed"
  fi
}

install_python "$PYTHON_VERSION"

if [[ "$INSTALL_LTS" == "1" ]]; then
  info "INSTALL_LTS=1 — also installing $PYTHON_VERSION_LTS"
  install_python "$PYTHON_VERSION_LTS"
else
  info "Skipping LTS Python ($PYTHON_VERSION_LTS). Run with INSTALL_LTS=1 if you need it."
fi

pyenv global "$PYTHON_VERSION"
success "Global Python: $(python --version 2>&1)"

# ═════════════════════════════════════════════════════════════════════════════
step "6 / uv — Modern Python Package Manager"
# ═════════════════════════════════════════════════════════════════════════════
if command_exists uv; then
  skip "uv ($(uv --version))"
else
  info "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  append_if_missing 'export PATH="$HOME/.cargo/bin:$PATH"' "$ZSHRC"
  export PATH="$HOME/.cargo/bin:$PATH"
  success "uv installed"
fi

# ruff — linting/formatting (installed as a uv tool, not into any project venv)
if command_exists ruff; then skip "ruff"
else uv tool install ruff && success "ruff installed"; fi

# ═════════════════════════════════════════════════════════════════════════════
step "7 / nvm — Node Version Manager"
# ═════════════════════════════════════════════════════════════════════════════
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"

NVM_INIT_BLOCK='
# ── nvm ──────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
autoload -U add-zsh-hook
load-nvmrc() {
  local nvmrc_path="$(nvm_find_nvmrc)"
  if [ -n "$nvmrc_path" ]; then
    local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")
    if [ "$nvmrc_node_version" = "N/A" ]; then nvm install
    elif [ "$nvmrc_node_version" != "$(nvm version)" ]; then nvm use; fi
  fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc'

if ! grep -q 'NVM_DIR' "$ZSHRC" 2>/dev/null; then
  echo "$NVM_INIT_BLOCK" >> "$ZSHRC"
  success "Added nvm init to $ZSHRC"
else
  skip "nvm init block in .zshrc"
fi

# Source nvm for this session and install Node LTS
NVM_SH="/opt/homebrew/opt/nvm/nvm.sh"
[[ -s "$NVM_SH" ]] && source "$NVM_SH"

if command_exists nvm; then
  if nvm list 2>/dev/null | grep -q "v${NODE_LTS}"; then
    skip "Node $NODE_LTS"
  else
    info "Installing Node.js LTS v${NODE_LTS}..."
    nvm install "$NODE_LTS"
    nvm use "$NODE_LTS"
    nvm alias default "$NODE_LTS"
    success "Node $(node --version 2>/dev/null) installed"
  fi
else
  warn "nvm not available in this session — Node install will run on next shell start"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "8 / direnv, Starship & Shell Hooks"
# ═════════════════════════════════════════════════════════════════════════════
# direnv
if ! grep -q 'direnv hook' "$ZSHRC" 2>/dev/null; then
  printf '\n# ── direnv ──────────────────────────────────────────────────────────────────\neval "$(direnv hook zsh)"\n' >> "$ZSHRC"
  success "direnv hook added to $ZSHRC"
else
  skip "direnv hook in .zshrc"
fi

# Starship prompt
if ! grep -q 'starship init' "$ZSHRC" 2>/dev/null; then
  printf '\n# ── Starship prompt ─────────────────────────────────────────────────────────\neval "$(starship init zsh)"\n' >> "$ZSHRC"
  success "Starship init added to $ZSHRC"
else
  skip "Starship in .zshrc"
fi

mkdir -p "$HOME/.config"
if [[ ! -f "$HOME/.config/starship.toml" ]]; then
  cat > "$HOME/.config/starship.toml" << 'TOML'
format = """
[$directory](bold blue)\
$git_branch$git_status\
$python$gcloud$nodejs\
$cmd_duration\
$line_break$character"""
[directory]
truncation_length = 4
truncate_to_repo = true
[python]
format = '[(\($virtualenv\) )](italic #f5a623)[${symbol}(${version})]($style) '
symbol = "🐍 "
detect_files = ["pyproject.toml","requirements.txt",".python-version","setup.py"]
[gcloud]
format = '[$symbol$account(@$domain)(\($region\))]($style) '
style = "bold blue"
symbol = "☁️  "
[git_branch]
format = '[$symbol$branch]($style) '
style = "bold purple"
[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
TOML
  success "Created ~/.config/starship.toml"
else
  skip "~/.config/starship.toml"
fi

# fzf keybindings
if ! grep -q 'fzf.zsh' "$ZSHRC" 2>/dev/null; then
  FZF_INSTALL="$(brew --prefix)/opt/fzf/install"
  [[ -f "$FZF_INSTALL" ]] && "$FZF_INSTALL" --key-bindings --completion --no-update-rc 2>/dev/null
  printf '\n[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh\nexport FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"\n' >> "$ZSHRC"
  success "fzf keybindings added"
else
  skip "fzf in .zshrc"
fi

# zoxide
if ! grep -q 'zoxide init' "$ZSHRC" 2>/dev/null; then
  printf '\neval "$(zoxide init zsh)"\nalias cd="z"\n' >> "$ZSHRC"
  success "zoxide added to $ZSHRC"
else
  skip "zoxide in .zshrc"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "9 / Git Global Config"
# ═════════════════════════════════════════════════════════════════════════════
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global push.default current
command_exists code && git config --global core.editor "code --wait" || git config --global core.editor "vim"
git config --global alias.lg "log --oneline --graph --decorate --all"
git config --global alias.st "status -sb"
git config --global alias.unstage "reset HEAD --"

GLOBAL_GI="$HOME/.gitignore_global"
cat > "$GLOBAL_GI" << 'GI'
.DS_Store
.env
.env.local
.env.*.local
*.env
!.env.example
!.env.template
__pycache__/
*.py[cod]
.venv/
venv/
*.egg-info/
dist/
build/
.pytest_cache/
.mypy_cache/
.ruff_cache/
node_modules/
.idea/
.vscode/
*.swp
*~
.terraform/
*.tfstate
*.tfstate.backup
GI

git config --global core.excludesfile "$GLOBAL_GI"
success "Git global config + .gitignore_global set"

# ═════════════════════════════════════════════════════════════════════════════
step "10 / PIP_REQUIRE_VIRTUALENV safety guard"
# ═════════════════════════════════════════════════════════════════════════════
# This single setting prevents accidental global pip installs —
# pip will refuse to run unless a venv is active.
if ! grep -q 'PIP_REQUIRE_VIRTUALENV' "$ZSHRC" 2>/dev/null; then
  printf '\n# Prevent accidental global pip installs — venv must be active\nexport PIP_REQUIRE_VIRTUALENV=1\n' >> "$ZSHRC"
  success "PIP_REQUIRE_VIRTUALENV=1 added to $ZSHRC"
else
  skip "PIP_REQUIRE_VIRTUALENV in .zshrc"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "11 / Directory Structure"
# ═════════════════════════════════════════════════════════════════════════════
for dir in \
  "$DEV_DIR" "$DEV_DIR/_templates" "$DEV_DIR/internal" \
  "$DEV_DIR/sandbox" "$DEV_DIR/clients" \
  "$ENVS_DIR" "$ENVS_DIR/gcp-tools" "$ENVS_DIR/data-tools"; do
  [[ -d "$dir" ]] && skip "$dir" || { mkdir -p "$dir" && success "Created $dir"; }
done

# ═════════════════════════════════════════════════════════════════════════════
step "12 / Shared Python Environments (~/.envs/)"
# ═════════════════════════════════════════════════════════════════════════════
# gcp-tools — GCP SDK packages
if [[ ! -f "$ENVS_DIR/gcp-tools/bin/pip" ]]; then
  info "Creating ~/.envs/gcp-tools venv..."
  python -m venv "$ENVS_DIR/gcp-tools"
  "$ENVS_DIR/gcp-tools/bin/pip" install -q --upgrade pip
  "$ENVS_DIR/gcp-tools/bin/pip" install -q \
    "google-cloud-bigquery[pandas]" google-cloud-storage \
    google-cloud-secret-manager google-cloud-logging
  success "gcp-tools venv ready"
else
  skip "~/.envs/gcp-tools"
fi

# data-tools — dbt, Snowflake, Databricks
if [[ ! -f "$ENVS_DIR/data-tools/bin/pip" ]]; then
  info "Creating ~/.envs/data-tools venv (dbt, Snowflake, Databricks)..."
  python -m venv "$ENVS_DIR/data-tools"
  "$ENVS_DIR/data-tools/bin/pip" install -q --upgrade pip
  "$ENVS_DIR/data-tools/bin/pip" install -q \
    dbt-core dbt-bigquery dbt-snowflake \
    "snowflake-connector-python[pandas]" snowflake-sqlalchemy
  success "data-tools venv ready"
else
  skip "~/.envs/data-tools"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "13 / Shell Aliases"
# ═════════════════════════════════════════════════════════════════════════════
if ! grep -q 'mcsquared.ai dev aliases' "$ZSHRC" 2>/dev/null; then
  cat >> "$ZSHRC" << 'ALIASES'

# ── mcsquared.ai dev aliases ─────────────────────────────────────────────────
alias venv='python -m venv .venv && source .venv/bin/activate && pip install --upgrade pip'
alias activate='source .venv/bin/activate'
alias deact='deactivate'
alias data-tools='source ~/.envs/data-tools/bin/activate && echo "✅ data-tools active"'
alias gcp-tools='source ~/.envs/gcp-tools/bin/activate && echo "✅ gcp-tools active"'
alias dev='cd ~/dev'
alias sandbox='cd ~/dev/sandbox'
alias internal='cd ~/dev/internal'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate --all -20'
alias gcm='git commit -m'
alias gpl='git pull --rebase'
alias gp='git push'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias gsandbox='gcloud config configurations activate sandbox 2>/dev/null && echo "☁️  GCP sandbox"'
alias gprod='gcloud config configurations activate production 2>/dev/null && echo "☁️  GCP production"'
alias reload='source ~/.zshrc && echo "✅ reloaded"'
alias path='echo $PATH | tr ":" "\n" | nl'
alias ports='lsof -i -P -n | grep LISTEN'
alias new-project='~/dev/_templates/new-project.sh'
ALIASES
  success "Dev aliases added to $ZSHRC"
else
  skip "dev aliases in .zshrc"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "14 / Claude Code Global Context (~/.claude/CLAUDE.md)"
# ═════════════════════════════════════════════════════════════════════════════
mkdir -p "$HOME/.claude"
if [[ ! -f "$HOME/.claude/CLAUDE.md" ]]; then
  cat > "$HOME/.claude/CLAUDE.md" << CLAUDEMD
# Global Claude Code Context — mcsquared.ai

## Developer
Pankaj Shroff, Founder & CEO, mcsquared.ai | macOS $ARCH

## Python
- Version manager: pyenv | Global: $PYTHON_VERSION
- Package manager: uv (preferred) or venv + pip
- Venvs: .venv/ inside each project root
- NEVER global pip installs without an active venv (PIP_REQUIRE_VIRTUALENV=1)

## Node.js
- Version manager: nvm | Default: Node $NODE_LTS LTS
- Pin per project via .nvmrc

## Code Standards
- Linting/formatting: ruff | Types: mypy --strict | Tests: pytest
- Type hints on all function signatures
- Async-first for I/O (asyncio + httpx, not requests)
- Config from env vars via pydantic-settings — never hardcoded

## Architecture Principles
- Adapter pattern for all external services (cloud-agnostic)
- 12-factor app (config from environment, stateless processes)
- Cloud-portable: build on GCP sandbox, adapters for AWS/Azure

## Cloud
- Primary: GCP sandbox (gcloud config configurations activate sandbox)
- Auth: ADC — gcloud auth application-default login
- Production portability: GCP → AWS → Azure via adapter interfaces
- Enterprise SoR adapters: Snowflake, Databricks, BigQuery, Palantir, Oracle

## Preferred Libraries
- LLM: anthropic SDK | HTTP: httpx | Data: pandas, polars
- Validation: pydantic v2 | Config: pydantic-settings
- GCP: google-cloud-* | AWS: boto3 | Data: snowflake-connector-python, databricks-sdk

## Project Layout
- ~/dev/internal/  — mcsquared.ai products
- ~/dev/sandbox/   — GCP sandbox experiments
- ~/dev/clients/   — client engagements
- ~/.envs/         — shared tool venvs (gcp-tools, data-tools)
CLAUDEMD
  success "Created ~/.claude/CLAUDE.md"
else
  skip "~/.claude/CLAUDE.md"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "15 / Claude Code CLI (Homebrew)"
# ═════════════════════════════════════════════════════════════════════════════
# Claude Code CLI is installed via Homebrew — NOT npm.
# This ensures `claude` is always in PATH (/opt/homebrew/bin/) regardless of
# nvm state or Node version. Updates via: brew upgrade claude-code
#
# The Claude Desktop app (GUI) is installed as a cask in step 4.

# 15a — Clean up any legacy npm-based Claude Code install
if command_exists npm; then
  if npm list -g @anthropic-ai/claude-code &>/dev/null 2>&1; then
    info "Removing legacy npm-based Claude Code install..."
    npm uninstall -g @anthropic-ai/claude-code
    success "Removed npm Claude Code (replaced by Homebrew)"
  else
    skip "no legacy npm Claude Code to remove"
  fi
fi

# 15b — Remove any stale npm prefix settings from earlier attempts
npm config delete prefix 2>/dev/null || true
if grep -qF "npm_config_prefix" "$ZSHRC" 2>/dev/null || grep -qF "NPM_GLOBAL" "$ZSHRC" 2>/dev/null; then
  TMP=$(mktemp)
  grep -v "npm_config_prefix\|NPM_GLOBAL\|npm-global\|npm global tools" "$ZSHRC" > "$TMP" && mv "$TMP" "$ZSHRC"
  success "Removed stale npm prefix lines from $ZSHRC"
else
  skip "no stale npm prefix lines in .zshrc"
fi

# 15c — Install Claude Code via Homebrew
if brew list claude-code &>/dev/null; then
  skip "claude-code ($(claude --version 2>/dev/null))"
else
  info "Installing Claude Code CLI via Homebrew..."
  brew install claude-code
  command_exists claude \
    && success "Claude Code installed: $(claude --version 2>/dev/null)" \
    || warn "brew install ran — reload shell (exec \$SHELL -l) then verify: which claude"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "16 / gcloud & AWS Install Reminders"
# ═════════════════════════════════════════════════════════════════════════════
if ! command_exists gcloud; then
  cat > "$HOME/SETUP-GCLOUD.sh" << 'GCSCRIPT'
#!/usr/bin/env bash
# Run separately — installs Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
# Then:
gcloud init
gcloud auth login
gcloud auth application-default login
gcloud config configurations create sandbox
# gcloud config set project YOUR_SANDBOX_PROJECT_ID
gcloud services enable aiplatform.googleapis.com bigquery.googleapis.com \
  run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com \
  storage.googleapis.com container.googleapis.com artifactregistry.googleapis.com
GCSCRIPT
  chmod +x "$HOME/SETUP-GCLOUD.sh"
  warn "gcloud not installed → ~/SETUP-GCLOUD.sh created. Run it after this script."
else
  skip "gcloud ($(gcloud --version 2>/dev/null | head -1))"
fi

if ! command_exists aws; then
  cat > "$HOME/SETUP-AWS.sh" << 'AWSSCRIPT'
#!/usr/bin/env bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "/tmp/AWSCLIV2.pkg"
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
aws --version
aws configure --profile sandbox
AWSSCRIPT
  chmod +x "$HOME/SETUP-AWS.sh"
  warn "aws not installed → ~/SETUP-AWS.sh created. Run it after this script."
else
  skip "aws ($(aws --version 2>/dev/null))"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "17 / Pre-flight Check Script"
# ═════════════════════════════════════════════════════════════════════════════
cat > "$DEV_DIR/preflight-check.sh" << 'PREFLIGHT'
#!/usr/bin/env bash
P="✅"; F="❌"; W="⚠️"
chk() { local n=$1 c=$2; local r=$(eval "$c" 2>/dev/null | head -1)
        [[ -n "$r" ]] && echo "  $P $n: $r" || echo "  $F $n: NOT FOUND"; }

echo "══ Dev Environment Pre-flight ══"
echo ""
echo "── Runtimes ──"
chk "python"  "python --version"
chk "pyenv"   "pyenv --version"
chk "node"    "node --version"
chk "nvm"     "nvm --version"
echo ""
echo "── Package Managers ──"
chk "uv"      "uv --version"
chk "pip"     "pip --version"
chk "brew"    "brew --version"
echo ""
echo "── Cloud CLIs ──"
chk "gcloud"  "gcloud --version"
chk "aws"     "aws --version"
chk "az"      "az --version"
echo ""
echo "── Dev Tools ──"
chk "git"     "git --version"
chk "gh"      "gh --version"
chk "docker"  "docker --version"
chk "direnv"  "direnv --version"
chk "ruff"    "ruff --version"
chk "starship" "starship --version"
chk "claude"  "claude --version"
echo ""
echo "── Python Hygiene ──"
WP=$(which python 2>/dev/null)
WPP=$(which pip 2>/dev/null)
[[ "$WP"  == *".pyenv"* ]] && echo "  $P python → pyenv: $WP"  || echo "  $F python NOT via pyenv: $WP"
[[ "$WPP" == *".pyenv"* ]] && echo "  $P pip → pyenv: $WPP"    || echo "  $F pip NOT via pyenv: $WPP"
echo ""
echo "── Shared Envs ──"
for e in gcp-tools data-tools; do
  [[ -f "$HOME/.envs/$e/bin/pip" ]] && echo "  $P ~/.envs/$e" || echo "  $W ~/.envs/$e: not created"
done
echo ""
echo "── GCP Auth ──"
if command -v gcloud &>/dev/null; then
  A=$(gcloud auth list 2>&1 | grep ACTIVE | awk '{print $2}')
  [[ -n "$A" ]] && echo "  $P gcloud auth: $A" || echo "  $F no active gcloud account"
  PR=$(gcloud config get-value project 2>/dev/null)
  [[ -n "$PR" ]] && echo "  $P GCP project: $PR" || echo "  $W GCP project not set"
else
  echo "  $F gcloud: not installed"
fi
echo ""
echo "══ Done ══"
PREFLIGHT
chmod +x "$DEV_DIR/preflight-check.sh"
success "Created ~/dev/preflight-check.sh"

# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  Setup complete!${RESET}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Python installed : ${BOLD}$PYTHON_VERSION${RESET} (only this version)"
echo ""
echo -e "${CYAN}Next steps:${RESET}"
echo "  1. Restart terminal  →  exec \$SHELL -l"
echo "  2. Verify claude:          which claude && claude --version"
echo "     (path should be /opt/homebrew/bin/claude)"
echo "  3. Verify no nvm warning:  open a new terminal — should be silent"
echo "  4. Verify env:             ~/dev/preflight-check.sh"
! command_exists gcloud && echo "  5. Install gcloud    →  bash ~/SETUP-GCLOUD.sh"
! command_exists aws    && echo "  6. Install AWS CLI   →  bash ~/SETUP-AWS.sh"
echo "  7. Set GCP project   →  gcloud config set project YOUR_PROJECT_ID"
echo "  8. Auth ADC          →  gcloud auth application-default login"
echo "  9. First project     →  new-project my-agent ai-agent internal"
echo ""
echo -e "${YELLOW}To also install Python 3.11.9 (LTS) in future:${RESET}"
echo "  INSTALL_LTS=1 ./mac-env-setup.sh"
echo ""
