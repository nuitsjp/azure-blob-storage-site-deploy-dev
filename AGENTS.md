# Repository Guidelines

## Primary Directive

- Think in English, interact with the user in Japanese.
- Write all explanations, documentation, and comments in Japanese.
- Use English for identifiers (class names, function names, variable names, parts of file names).

## Role

This repository is a development meta-repository. The primary implementation targets are the following child repositories:

- `repos/product`: `azure-blob-storage-site-deploy`
- `repos/e2e`: `azure-blob-storage-site-deploy-e2e`

## Working Rules

- Never edit the `main` branch directly in `repos/product` / `repos/e2e`.
- Create a working branch in the target repository before making changes.
- Clearly report which repository was changed.
- After updating submodules, verify the state with `git submodule status`.

## Design Documents

Design documents are consolidated in `docs/`:

- `docs/design.md` — Product design (background, requirements, constraints, interface)
- `docs/architecture.md` — Implementation structure and script decomposition
- `docs/deploy.md` — Detailed design of deploy.sh
- `docs/cleanup.md` — Detailed design of cleanup.sh
- `docs/e2e.md` — Detailed design of E2E tests

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

# Status
just status             # Check status of each repository
just log                # Show logs for each repository

# Create working branches
just branch-product NAME  # Create branch in repos/product
just branch-e2e NAME      # Create branch in repos/e2e
```

## Testing Guidelines

- When adding implementation code, also add tests following the Bats structure in `tests/`.
- Test priority: Unit tests for pure functions → Flow tests with mocks → E2E tests.
- Always run the appropriate test/verification commands for the scope of changes before creating a PR.

## Commit & PR Guidelines

- Conventional Commit style: `feat: ...`, `docs: ...`, `fix: ...`. Japanese commit messages are also acceptable.
- PR body should include: purpose, changed files/scope, verification performed (commands and results, e.g., `34 tests pass`), and impact scope.
- Do not close child Issues during PR creation or review. As a rule, close them after PR merge and update the parent Issue's checklist at the same time.
- Explicitly note any cross-repository impacts.
