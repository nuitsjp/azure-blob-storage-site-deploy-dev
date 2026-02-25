> [日本語版](README.ja.md)

# azure-blob-storage-site-deploy-dev

A development meta-repository for working with the `azure-blob-storage-site-deploy` action and its E2E test repository in a single workspace.

## Repository Structure

```text
azure-blob-storage-site-deploy-dev/
├── repos/
│   ├── product/   # azure-blob-storage-site-deploy (Composite Action)
│   └── e2e/       # azure-blob-storage-site-deploy-e2e (E2E test repository)
├── scripts/       # Dev repository scripts
│   ├── test.sh        # Test execution facade
│   ├── release.sh     # Release script
│   └── e2e/           # E2E orchestrator (local execution scripts)
└── docs/          # Design documents
```

| Repository | Role | URL |
|---|---|---|
| **dev** (this repository) | Development hub / test runner | [azure-blob-storage-site-deploy-dev](https://github.com/nuitsjp/azure-blob-storage-site-deploy-dev) |
| **product** | Composite Action | [azure-blob-storage-site-deploy](https://github.com/nuitsjp/azure-blob-storage-site-deploy) |
| **e2e** | E2E test repository | [azure-blob-storage-site-deploy-e2e](https://github.com/nuitsjp/azure-blob-storage-site-deploy-e2e) |

Git dependency direction: `e2e → product` (E2E references the product action via `uses:`)

## Setup

### 1. Clone the Repository and Initialize Submodules

```bash
git clone https://github.com/nuitsjp/azure-blob-storage-site-deploy-dev.git
cd azure-blob-storage-site-deploy-dev
git submodule update --init --recursive
```

### 2. Install just

This repository uses the task runner [just](https://github.com/casey/just).

```bash
# macOS
brew install just

# Linux / WSL (prebuilt binary)
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
```

### 3. Development Environment Setup

```bash
just setup
```

`just setup` performs the following steps in sequence:

- Installs **gh** / **jq** (supports Homebrew / apt-get)
- Installs **bats-core** (locally into `repos/product/.tools/`)
- Runs **doctor** to verify all prerequisites

If `gh` is not yet authenticated, it will prompt you to run `gh auth login` and exit.

## Usage

Run `just` to see all available tasks. Key commands:

```bash
just test             # Unit + flow + E2E (default)
just test-unit        # Unit tests only
just test-flow        # Flow tests only
just test-e2e         # E2E tests (requires live Azure / gh / jq)
just release v1.2.3   # Release with specified version
just release-auto     # Auto-increment patch version
just doctor           # Verify prerequisites
just status           # Check status of each repository
just log              # View logs of each repository
```

## Development Workflow

### Basic Flow

1. **Create a feature branch** -- Create a branch inside `repos/product` or `repos/e2e` (never edit `main` directly)
2. **Implement** -- Edit scripts under `repos/product/scripts/`
3. **Unit & flow tests** -- Get fast feedback with `just test-unit` / `just test-flow`
4. **Create a PR** -- Open a PR in the product repository (CI runs tests automatically)
5. **E2E tests** -- Before release, verify against a live Azure environment with `just test-e2e` (or `just test`)
6. **Merge & release** -- After merging the PR, create a tag and publish a GitHub Release with `just release v1.2.3`

### Release

Always run the full test suite before releasing to ensure everything passes.

```bash
just test             # Run unit + flow + E2E tests together
just release v1.2.3   # Release with specified version
just release-auto     # Auto-increment patch version
```

In addition to the semantic versioning tag (`v1.2.3`), the major version tag (`v1`) is automatically updated as well.

## Design Documents

| Document | Description |
|---|---|
| [`docs/design.md`](docs/design.md) | Product design (background, requirements, constraints, interface) |
| [`docs/architecture.md`](docs/architecture.md) | Implementation structure and script decomposition |
| [`docs/deploy.md`](docs/deploy.md) | Detailed design of deploy.sh |
| [`docs/cleanup.md`](docs/cleanup.md) | Detailed design of cleanup.sh |
| [`docs/e2e.md`](docs/e2e.md) | Detailed design of E2E tests |
