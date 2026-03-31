#!/usr/bin/env bash
# =============================================================================
# new-project.sh — Project Scaffolding Script
# mcsquared.ai | Claude Code Enterprise AI Systems
#
# Usage: ./new-project.sh <project-name> <type> [category]
#
# Types: ai-agent | data-pipeline | python-service | full-stack
# Category: internal | clients/<client-name> | sandbox (default: internal)
#
# Examples:
#   ./new-project.sh context-engine ai-agent internal
#   ./new-project.sh bigquery-pipeline data-pipeline sandbox
#   ./new-project.sh api-gateway python-service clients/acme-corp
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  →${RESET} $1"; }
success() { echo -e "${GREEN}  ✓${RESET} $1"; }
warn()    { echo -e "${YELLOW}  !${RESET} $1"; }

# ── Args ─────────────────────────────────────────────────────────────────────
PROJECT_NAME="${1:-}"
PROJECT_TYPE="${2:-python-service}"
CATEGORY="${3:-internal}"

if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "${BOLD}Usage:${RESET} $0 <project-name> <type> [category]"
  echo ""
  echo "Types:    ai-agent | data-pipeline | python-service | full-stack"
  echo "Category: internal | sandbox | clients/<client-name>"
  echo ""
  echo "Example:  $0 context-engine ai-agent internal"
  exit 1
fi

DEV_DIR="$HOME/dev"
PROJECT_DIR="$DEV_DIR/$CATEGORY/$PROJECT_NAME"
PYTHON_VERSION="3.12.3"
NODE_VERSION="20"

echo -e "${BOLD}${CYAN}══ Creating project: $PROJECT_NAME ══${RESET}"
echo "  Type    : $PROJECT_TYPE"
echo "  Category: $CATEGORY"
echo "  Path    : $PROJECT_DIR"
echo ""

# ── Create directories ───────────────────────────────────────────────────────
mkdir -p "$PROJECT_DIR"/{src,tests,docs,scripts,infra}
mkdir -p "$PROJECT_DIR"/src/"${PROJECT_NAME//-/_}"
mkdir -p "$PROJECT_DIR"/tests/{unit,integration}
mkdir -p "$PROJECT_DIR"/infra/{gcp,aws,azure}

success "Directory structure created"

cd "$PROJECT_DIR"

# ── .python-version ──────────────────────────────────────────────────────────
echo "$PYTHON_VERSION" > .python-version
success ".python-version: $PYTHON_VERSION"

# ── .nvmrc ───────────────────────────────────────────────────────────────────
echo "$NODE_VERSION" > .nvmrc
success ".nvmrc: $NODE_VERSION"

# ── .gitignore ───────────────────────────────────────────────────────────────
cat > .gitignore << 'GITIGNORE'
# Python
__pycache__/
*.py[cod]
*.pyo
.venv/
venv/
env/
*.egg-info/
dist/
build/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.coverage
htmlcov/
*.coverage
.hypothesis/

# Environment & Secrets — NEVER commit these
.env
.env.local
.env.*.local
*.env
!.env.example
!.env.template

# Node
node_modules/
.npm/
.eslintcache
npm-debug.log*

# IDEs
.idea/
.vscode/
*.swp
*~

# macOS
.DS_Store
.AppleDouble

# Cloud & IaC
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl

# Logs
*.log
logs/

# Docker
.docker/

# Test outputs
reports/
coverage/
GITIGNORE

success ".gitignore created"

# ── .env.example ─────────────────────────────────────────────────────────────
cat > .env.example << ENVEXAMPLE
# =============================================================================
# Environment Variables Template
# Copy to .env and fill in real values. NEVER commit .env
# =============================================================================

# GCP
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GCP_REGION=us-central1

# Anthropic (Claude)
ANTHROPIC_API_KEY=sk-ant-api03-...

# Application
APP_ENV=development
LOG_LEVEL=INFO
APP_PORT=8080
ENVEXAMPLE

# Add platform-specific vars based on type
if [[ "$PROJECT_TYPE" == "data-pipeline" ]] || [[ "$PROJECT_TYPE" == "ai-agent" ]]; then
  cat >> .env.example << 'ENVEXTRA'

# Snowflake (if used)
# SNOWFLAKE_ACCOUNT=your-account.snowflakecomputing.com
# SNOWFLAKE_USER=your_user
# SNOWFLAKE_DATABASE=your_db
# SNOWFLAKE_SCHEMA=public
# SNOWFLAKE_WAREHOUSE=your_wh
# SNOWFLAKE_ROLE=your_role
# SNOWFLAKE_PRIVATE_KEY_PATH=~/.ssh/snowflake_rsa_key.p8

# Databricks (if used)
# DATABRICKS_HOST=https://your-workspace.azuredatabricks.net
# DATABRICKS_TOKEN=dapi...

# OpenAI (if used alongside Claude)
# OPENAI_API_KEY=sk-...
ENVEXTRA
fi

success ".env.example created"

# ── .envrc (direnv) ──────────────────────────────────────────────────────────
cat > .envrc << 'ENVRC'
# direnv — auto-activate venv and load .env when entering this directory
# Run: direnv allow . (first time only)

# Activate project venv
if [[ -d .venv ]]; then
  source .venv/bin/activate
fi

# Load .env file (if exists)
if [[ -f .env ]]; then
  dotenv .env
fi

# Set GCP sandbox as default for this project
export CLOUDSDK_ACTIVE_CONFIG_NAME=sandbox
ENVRC

success ".envrc created"
warn "Run 'direnv allow .' after customizing .envrc"

# ── pyproject.toml ────────────────────────────────────────────────────────────
PKG_NAME="${PROJECT_NAME//-/_}"
cat > pyproject.toml << PYPROJECT
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "${PROJECT_NAME}"
version = "0.1.0"
description = "$(echo $PROJECT_TYPE | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g') — mcsquared.ai"
requires-python = ">=${PYTHON_VERSION%.*}"
readme = "README.md"

dependencies = [
PYPROJECT

# Add type-specific dependencies
if [[ "$PROJECT_TYPE" == "ai-agent" ]]; then
  cat >> pyproject.toml << 'DEPS'
  "anthropic>=0.40.0",
  "httpx>=0.27.0",
  "pydantic>=2.0.0",
  "python-dotenv>=1.0.0",
  "google-cloud-bigquery>=3.0.0",
  "structlog>=24.0.0",
]
DEPS
elif [[ "$PROJECT_TYPE" == "data-pipeline" ]]; then
  cat >> pyproject.toml << 'DEPS'
  "pandas>=2.0.0",
  "polars>=0.20.0",
  "google-cloud-bigquery[pandas]>=3.0.0",
  "pydantic>=2.0.0",
  "python-dotenv>=1.0.0",
  "structlog>=24.0.0",
]
DEPS
else
  cat >> pyproject.toml << 'DEPS'
  "httpx>=0.27.0",
  "pydantic>=2.0.0",
  "python-dotenv>=1.0.0",
  "structlog>=24.0.0",
]
DEPS
fi

cat >> pyproject.toml << 'PYPROJECTEND'

[project.optional-dependencies]
dev = [
  "pytest>=8.0.0",
  "pytest-asyncio>=0.23.0",
  "pytest-cov>=5.0.0",
  "ruff>=0.5.0",
  "mypy>=1.10.0",
  "httpx>=0.27.0",  # for test client
]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "ANN", "B", "C4", "SIM"]
ignore = ["ANN101", "ANN102"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"

[tool.mypy]
python_version = "3.12"
strict = true
ignore_missing_imports = true

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
addopts = "--cov=src --cov-report=term-missing"

[tool.coverage.run]
source = ["src"]
omit = ["tests/*"]
PYPROJECTEND

success "pyproject.toml created"

# ── Makefile ──────────────────────────────────────────────────────────────────
cat > Makefile << 'MAKEFILE'
# =============================================================================
# Makefile — common project commands
# Usage: make <target>
# =============================================================================
.PHONY: help dev install test lint format typecheck clean docker-build docker-run

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

dev: install  ## Set up development environment
	@echo "✅ Dev environment ready. Run: source .venv/bin/activate"

install:  ## Install dependencies
	@python -m venv .venv
	@.venv/bin/pip install --upgrade pip
	@.venv/bin/pip install -e ".[dev]"

install-uv:  ## Install with uv (faster)
	@uv sync

test:  ## Run tests
	@pytest tests/ -v

test-unit:  ## Run unit tests only
	@pytest tests/unit/ -v

test-integration:  ## Run integration tests
	@pytest tests/integration/ -v --timeout=60

lint:  ## Lint with ruff
	@ruff check src/ tests/

format:  ## Format with ruff
	@ruff format src/ tests/
	@ruff check --fix src/ tests/

typecheck:  ## Type check with mypy
	@mypy src/

check: lint typecheck test  ## Run all checks (lint + types + tests)

clean:  ## Clean build artifacts
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@rm -rf .pytest_cache .mypy_cache .ruff_cache dist build *.egg-info

docker-build:  ## Build Docker image
	@docker build -t $(shell basename $(CURDIR)):latest .

docker-run:  ## Run Docker container locally
	@docker run --env-file .env -p 8080:8080 $(shell basename $(CURDIR)):latest

gcp-deploy:  ## Deploy to GCP Cloud Run (sandbox)
	@gcloud run deploy $(shell basename $(CURDIR)) \
		--source . \
		--region us-central1 \
		--allow-unauthenticated
MAKEFILE

success "Makefile created"

# ── Source package init ───────────────────────────────────────────────────────
cat > "src/${PKG_NAME}/__init__.py" << INIT
"""${PROJECT_NAME} — mcsquared.ai"""
__version__ = "0.1.0"
INIT

# ── Config module ─────────────────────────────────────────────────────────────
cat > "src/${PKG_NAME}/config.py" << 'CONFIG'
"""
Application configuration — reads from environment variables only.
Never hardcode values here. Use .env for local dev, Secret Manager for production.
"""
import os
from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Validated application settings from environment."""

    # GCP
    google_cloud_project: str = Field(default="", env="GOOGLE_CLOUD_PROJECT")
    gcp_region: str = Field(default="us-central1", env="GCP_REGION")

    # Anthropic
    anthropic_api_key: str = Field(default="", env="ANTHROPIC_API_KEY")

    # Application
    app_env: str = Field(default="development", env="APP_ENV")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    app_port: int = Field(default=8080, env="APP_PORT")

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache
def get_settings() -> Settings:
    """Cached settings instance — call this everywhere."""
    return Settings()
CONFIG

success "src/${PKG_NAME}/config.py created"

# ── Tests ─────────────────────────────────────────────────────────────────────
cat > "tests/__init__.py" << 'EOF'
EOF

cat > "tests/unit/__init__.py" << 'EOF'
EOF

cat > "tests/unit/test_config.py" << TESTCONFIG
"""Tests for configuration module."""
import os
import pytest
from src.${PKG_NAME}.config import get_settings


def test_settings_load():
    """Settings should load with defaults."""
    settings = get_settings()
    assert settings.app_env in ("development", "production", "staging")
    assert settings.app_port > 0


def test_settings_env_override(monkeypatch):
    """Settings should pick up environment variables."""
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.setenv("APP_PORT", "9090")
    # Clear cache for test
    get_settings.cache_clear()
    settings = get_settings()
    assert settings.app_env == "staging"
    assert settings.app_port == 9090
    get_settings.cache_clear()  # Reset after test
TESTCONFIG

success "Tests scaffolded"

# ── README.md ─────────────────────────────────────────────────────────────────
cat > README.md << README
# ${PROJECT_NAME}

> $(echo $PROJECT_TYPE | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g') · mcsquared.ai

## Quick Start

\`\`\`bash
# 1. Set up environment
make dev
source .venv/bin/activate

# 2. Copy and configure .env
cp .env.example .env
# Edit .env with your values

# 3. Run tests
make test

# 4. Start development
make run
\`\`\`

## Development Commands

| Command | Description |
|---------|-------------|
| \`make dev\` | Set up development environment |
| \`make test\` | Run all tests |
| \`make lint\` | Lint with ruff |
| \`make format\` | Format code |
| \`make typecheck\` | Type check with mypy |
| \`make check\` | Run all checks |
| \`make docker-build\` | Build Docker image |
| \`make gcp-deploy\` | Deploy to GCP Cloud Run |

## Architecture

See [CLAUDE.md](CLAUDE.md) for full architecture context.

## Environment Variables

See [.env.example](.env.example) for all required and optional variables.
README

success "README.md created"

# ── CLAUDE.md ─────────────────────────────────────────────────────────────────
CURRENT_DATE=$(date +%Y-%m-%d)
cat > CLAUDE.md << CLAUDEMD
# ${PROJECT_NAME} — Claude Code Context

> Last updated: ${CURRENT_DATE}
> Type: ${PROJECT_TYPE} | Category: ${CATEGORY} | Python: ${PYTHON_VERSION}

## Project Overview

[FILL IN: 2-3 sentences describing what this system does, the problem it solves,
and who uses it.]

## Tech Stack

- **Runtime**: Python ${PYTHON_VERSION} (managed via pyenv)
- **Package management**: uv (pyproject.toml)
- **Cloud**: GCP (primary sandbox), portable to AWS/Azure
- **LLM**: Anthropic Claude via \`anthropic\` SDK
- **Testing**: pytest + pytest-asyncio
- **Linting**: ruff | Types: mypy | Format: ruff format

## Repository Structure

\`\`\`
src/${PKG_NAME}/
├── __init__.py
├── config.py        # Settings from env vars (pydantic-settings)
├── [add more as you build]
tests/
├── unit/
└── integration/
\`\`\`

## Common Commands (run from project root)

\`\`\`bash
make dev             # Set up venv and install deps
make test            # Run all tests
make check           # Lint + types + tests
make format          # Auto-format code
make docker-build    # Build container
make gcp-deploy      # Deploy to GCP Cloud Run (sandbox)
\`\`\`

## Architecture Decisions

[FILL IN: Key decisions and the reasoning behind them. E.g.:]
- Why this data model
- Why this async pattern
- Why this cloud service over alternatives

## Data Flow

[FILL IN: Describe the main data flow through the system]

## GCP Resources Used

[FILL IN: List GCP services this project uses]
- Project: \`\${GOOGLE_CLOUD_PROJECT}\`
- Region: us-central1
- Services: [list]

## Integration Points

[FILL IN: External systems this connects to]

## Known Constraints & Gotchas

[FILL IN: Things Claude should know that aren't obvious from the code]

## TODOs / Open Questions

[FILL IN: Current work in progress or decisions not yet made]
CLAUDEMD

success "CLAUDE.md created"

# ── Dockerfile ────────────────────────────────────────────────────────────────
cat > Dockerfile << 'DOCKERFILE'
FROM python:3.12-slim AS builder

WORKDIR /app

# Install uv for fast builds
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-dev 2>/dev/null || uv sync --no-dev

# Production image
FROM python:3.12-slim AS production

WORKDIR /app

# Copy venv from builder
COPY --from=builder /app/.venv ./.venv

# Copy application
COPY src/ ./src/

# Security: non-root user
RUN useradd -m -u 1000 -s /bin/bash app && chown -R app:app /app
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:${APP_PORT:-8080}/health || exit 1

ENV PATH="/app/.venv/bin:$PATH"
CMD ["python", "-m", "src.main"]
DOCKERFILE

cat > .dockerignore << 'DOCKERIGNORE'
.venv/
venv/
__pycache__/
*.pyc
.env
.env.*
!.env.example
.git/
.gitignore
*.md
tests/
docs/
.pytest_cache/
.mypy_cache/
.ruff_cache/
DOCKERIGNORE

success "Dockerfile + .dockerignore created"

# ── Git init ─────────────────────────────────────────────────────────────────
if [[ ! -d .git ]]; then
  git init -q
  git add -A
  git commit -q -m "chore: initial project scaffold (${PROJECT_TYPE})"
  success "Git repo initialized with initial commit"
else
  warn "Git repo already exists — skipping init"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  Project Created: ${PROJECT_NAME}${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${RESET}"
echo ""
echo -e "  📁 ${BOLD}$PROJECT_DIR${RESET}"
echo ""
echo -e "${CYAN}Next steps:${RESET}"
echo "  1. cd $PROJECT_DIR"
echo "  2. direnv allow .            (approve .envrc)"
echo "  3. cp .env.example .env      (fill in real values)"
echo "  4. make dev                  (create venv + install deps)"
echo "  5. Open CLAUDE.md and fill in architecture context"
echo "  6. Start building with: claude"
echo ""
