# [Project Name] — Claude Code Context

> Last updated: [DATE]
> Type: [ai-agent | data-pipeline | python-service | full-stack]
> Status: [active | experimental | production]

---

## Project Overview

[2-3 sentences: what this system does, the business problem it solves, who the end user is.]

**Key value proposition:** [One sentence on the core capability]

---

## Tech Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Language | Python 3.12 | pyenv managed |
| Packages | uv + pyproject.toml | `uv sync` to install |
| LLM | Anthropic Claude | `anthropic` SDK |
| Cloud (primary) | GCP | sandbox: `[PROJECT_ID]` |
| Compute | Cloud Run / GKE | serverless preferred |
| Storage | BigQuery + GCS | structured + blob |
| Auth | ADC (gcloud) | key-pair for Snowflake |
| Testing | pytest + pytest-asyncio | |
| Linting | ruff | replaces black/flake8/isort |
| Types | mypy (strict) | |

---

## Repository Structure

```
src/[package_name]/
├── __init__.py
├── config.py          # All config from env vars via pydantic-settings
├── models/            # Pydantic data models
├── services/          # Business logic (stateless functions)
├── adapters/          # External service adapters (cloud-agnostic interfaces)
│   ├── llm/           # LLM provider adapters (anthropic, openai)
│   ├── data/          # Data store adapters (bigquery, snowflake, etc.)
│   └── compute/       # Cloud compute adapters
├── api/               # API layer (FastAPI or Cloud Run handler)
└── utils/             # Shared utilities

tests/
├── unit/              # Pure function tests, no external calls
├── integration/       # Tests against real (sandbox) services
└── e2e/               # End-to-end workflow tests

infra/
├── gcp/               # Terraform/Pulumi for GCP
├── aws/               # AWS (for portability testing)
└── azure/             # Azure (for client compatibility)
```

---

## Common Commands

```bash
# Development
make dev              # Create venv + install all deps
make test             # Run full test suite
make check            # lint + typecheck + tests (run before PR)
make format           # Auto-format with ruff

# Run
make run              # Start local development server
make docker-build     # Build container image
make docker-run       # Run container locally with .env

# Deploy (sandbox)
make gcp-deploy       # Deploy to GCP Cloud Run (sandbox project)

# Data platform tools (if applicable)
data-tools            # Activate ~/.envs/data-tools/ venv
dbt run               # Run dbt models (from data-tools venv)
```

---

## Architecture

### Core Patterns

- **Adapter pattern**: All external services (LLMs, data platforms, cloud APIs) go through
  adapter interfaces. Swapping cloud providers = implementing a new adapter, not refactoring core logic.

- **Config from environment**: `src/[package]/config.py` uses `pydantic-settings`. All values
  come from env vars. `.env` for local dev, GCP Secret Manager for production.

- **Async-first I/O**: Use `asyncio` + `httpx` for all network calls. Never use `requests`
  in new code.

- **Typed throughout**: All function signatures have type annotations. `mypy --strict` must pass.

### Data Flow

```
[Data Source] → [Adapter] → [Service Layer] → [LLM/Processing] → [Output/Storage]
```

[Describe the specific data flow for THIS project in 3-5 steps]

---

## External Integrations

| System | Type | Auth Method | Environment Variable |
|--------|------|-------------|---------------------|
| Anthropic Claude | LLM API | API Key | `ANTHROPIC_API_KEY` |
| GCP BigQuery | Data Warehouse | ADC (gcloud) | `GOOGLE_CLOUD_PROJECT` |
| [Add others] | | | |

---

## GCP Resources

- **Project**: `$GOOGLE_CLOUD_PROJECT` (set in .env)
- **Region**: us-central1
- **Cloud Run service**: [service-name]
- **BigQuery dataset**: [dataset-name]
- **GCS bucket**: [bucket-name]
- **Secret Manager secrets**: [list]

---

## Testing Strategy

```bash
# Unit tests — fast, no external calls, use mocks for adapters
pytest tests/unit/ -v

# Integration tests — hit real sandbox services (needs .env configured)
pytest tests/integration/ -v --timeout=60

# Before merging — run everything
make check
```

**Mocking pattern**: Adapters are interfaces. Tests inject mock adapters.
Never mock at the HTTP level (httpx) — mock at the adapter interface.

---

## Architecture Decisions

### [Decision 1: e.g., Why Cloud Run over GKE]
**Context**: [What led to this choice]
**Decision**: [What was chosen]
**Consequences**: [Trade-offs]

### [Decision 2: e.g., Why Polars over Pandas for large datasets]
...

---

## Known Constraints & Gotchas

- [Thing that's non-obvious that will cause confusion if Claude doesn't know it]
- [Specific library version constraint and why]
- [Cloud service limit or quota to be aware of]
- [Integration quirk (e.g., Snowflake connection pooling behavior)]

---

## Current Work in Progress

- [ ] [Current sprint item 1]
- [ ] [Current sprint item 2]
- [ ] [Open architectural question]

---

## Environment Variables

See `.env.example` for the full list. Key variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `GOOGLE_CLOUD_PROJECT` | Yes | GCP project ID |
| `ANTHROPIC_API_KEY` | Yes | Claude API key |
| `APP_ENV` | No | development/staging/production (default: development) |
| `LOG_LEVEL` | No | INFO/DEBUG/WARNING (default: INFO) |

---

## Portability Notes

This system is designed to be portable across cloud providers. The adapter pattern ensures:

- **Compute**: Cloud Run (GCP) → Lambda (AWS) → Container Apps (Azure) — change deploy target
- **Storage**: BigQuery → Redshift → Synapse — implement new data adapter
- **Object store**: GCS → S3 → Azure Blob — implement new storage adapter
- **Secrets**: Secret Manager → Secrets Manager → Key Vault — implement new secrets adapter

Target enterprise Systems of Record that may need adapters:
- Snowflake (`snowflake-connector-python`)
- Databricks (`databricks-sdk`)
- Palantir Foundry (`palantir-oauth-client`)
- Azure/MSFT Data Warehouse (`pyodbc` + ODBC driver)
- Oracle (`oracledb`)
