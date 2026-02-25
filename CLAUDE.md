# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Policy

- Think in English, interact with the user in Japanese.
- Write all explanations, documentation, and comments in Japanese.
- Use English for identifiers (class names, function names, variable names, parts of file names).
- Commit messages may be in Japanese. Use Conventional Commits style (`feat:`, `docs:`, `fix:`, etc.).

## Repository Overview

A development meta-repository. It bundles two independent repositories as submodules and provides a hub for AI coding agents to work across them.

- **`repos/product`** — `azure-blob-storage-site-deploy`: A GitHub Actions Composite Action for deploying static sites to Azure Blob Storage
- **`repos/e2e`** — `azure-blob-storage-site-deploy-e2e`: E2E tests for the above action

Git dependency direction: `e2e → product` (E2E references the product action via `uses:`)

## Branching Rules

- **Never edit the `main` branch directly** in `repos/product` / `repos/e2e`. Always create a working branch.
- Clearly report which repository was changed.

## Common Commands

Uses the task runner `just`. Run `just` to see the full list of available tasks.

```bash
# Setup
just setup              # Development environment setup (gh/jq, bats-core, doctor)
just doctor             # Prerequisites diagnostics

# Testing
just test               # Unit + Flow + E2E (default)
just test-unit          # Unit tests only
just test-flow          # Flow tests only
just test-e2e           # E2E tests (requires real Azure / gh / jq)

# Release
just release v1.2.3     # Release with specified version
just release-auto       # Auto-increment patch version

# Submodule / Status
just status             # Check status of each repository
just log                # Show logs for each repository

# Create working branches
just branch-product NAME  # Create branch in repos/product
just branch-e2e NAME      # Create branch in repos/e2e
```

## Design Documents

Design documents are consolidated in the `docs/` directory of the meta-repository:

- [`docs/design.md`](docs/design.md) — Product design (background, requirements, constraints, interface)
- [`docs/architecture.md`](docs/architecture.md) — Implementation structure and script decomposition
- [`docs/deploy.md`](docs/deploy.md) — Detailed design of deploy.sh
- [`docs/cleanup.md`](docs/cleanup.md) — Detailed design of cleanup.sh
- [`docs/e2e.md`](docs/e2e.md) — Detailed design of E2E tests

## Architecture

### Product (`repos/product`) — Composite Action

Implemented in bash. A shell-based Composite Action with no build step.

The fundamental design principle is separation of logic and side effects:

1. **Logic Layer** (`scripts/lib/validate.sh`, `scripts/lib/prefix.sh`) — Pure functions, no external dependencies
2. **Effect Layer** (`scripts/lib/azure.sh`) — Thin wrapper around `az` CLI, testable with mocks
3. **Entrypoints** (`scripts/deploy.sh`, `scripts/cleanup.sh`) — Orchestrators that combine Logic + Effect, called from `action.yml`

During testing, `tests/helpers/mock_azure.sh` replaces `az` functions with mocks that record call arguments to a log file for assertions.

### E2E (`repos/e2e`) — E2E Test Repository

Contains only the minimum resources needed as a "consumer" of the Composite Action:

- `.github/workflows/deploy.yml` — Deploy workflow triggered by push/PR events
- `docs/` — Static site content for testing

E2E test execution scripts are located in the dev repository's `scripts/e2e/`:

- `scripts/e2e/orchestrator.sh` — Runs E2E scenarios covering the full lifecycle
- `scripts/e2e/lib.sh` — Shared helper functions
- `scripts/e2e/verify.sh` — HTTP verification script (retry and content validation)

### Test Strategy

| Test Layer | Location | Azure Resources | Execution Timing |
|---|---|---|---|
| Unit tests | `repos/product/tests/unit/` | Not required | On PR creation/update |
| Flow tests | `repos/product/tests/flow/` (az mocked) | Not required | On PR creation/update |
| E2E tests | `scripts/e2e/` (run locally from dev repository) | Required | Manual / Pre-release |

CI runs unit tests and flow tests on each PR via `repos/product/.github/workflows/test-unit.yml`.

### Key Design Decisions

- **PR number-based prefix** (`pr-<number>`): Uses PR numbers instead of branch names. Avoids issues with Japanese character encoding, slash interpretation as directory separators, and name collisions with persistent branches.
- **File sync strategy**: Fully deletes the prefix directory before uploading (prevents stale files from remaining)
- **OIDC authentication**: Connects to Azure via Federated Credentials (no secrets required)
- **Composite Action over Reusable Workflow**: Runs as a step within the caller's job (no overhead of spinning up a separate job)
- **Trailing slash in URLs**: Azure Blob Storage does not auto-redirect `/pr-42` to `/pr-42/`, so URLs must always include a trailing `/`

## Coding Conventions

- File names: lowercase, tests follow `test_*.bats`
- Bash scripts: decompose into small functions, isolate side effects in wrappers (`scripts/lib/azure.sh`)
- Test priority: Unit tests (pure functions) → Flow tests (mocked) → E2E (real Azure environment, external repository)
- PR staging prefix: `pr-<number>`
