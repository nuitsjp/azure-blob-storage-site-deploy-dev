> [日本語版](architecture.ja.md)

# architecture

## Document Map

- [`design.md`](design.md): Product design (background, requirements, constraints, interface)
- `architecture.md` (this document): Implementation structure and script organization
- [`deploy.md`](deploy.md) / [`cleanup.md`](cleanup.md): Detailed design for each script
- [`e2e.md`](e2e.md): Detailed design for E2E tests

## Implementation Technology

### Composite Action

This action is implemented as a Composite Action. The reasons for choosing Composite Action over Reusable Workflow (`workflow_call`) are as follows.

- It runs as a step within the caller's job, eliminating the overhead of spawning a separate job
- Logic can be separated at the step level, resulting in high testability

### bash

Internal logic is implemented in bash.

- Pre-installed on GitHub Actions runners (`ubuntu-latest`), requiring no additional installation
- `az cli` is also pre-installed on runners, enabling Azure operations without any environment setup
- No dependency on runtimes such as Python or Node.js, resulting in lightweight execution

---

## Directory Structure

```
azure-blob-storage-site-deploy/
├── action.yml                      # Composite Action definition
├── scripts/
│   ├── lib/
│   │   ├── validate.sh             # Input validation functions
│   │   ├── prefix.sh               # Prefix generation and URL construction
│   │   └── azure.sh                # az cli call wrapper (side-effect layer)
│   ├── deploy.sh                   # Entry point for the deploy action
│   └── cleanup.sh                  # Entry point for the cleanup action
├── tests/
│   ├── unit/
│   │   ├── test_validate.bats      # Validation tests
│   │   └── test_prefix.bats        # Prefix generation tests
│   ├── flow/
│   │   ├── test_deploy.bats        # Deploy flow tests (az mocked)
│   │   └── test_cleanup.bats       # Cleanup flow tests (az mocked)
│   └── helpers/
│       └── mock_azure.sh           # az cli mock (for unit and flow tests)
├── .github/
│   └── workflows/
│       └── test-unit.yml           # Unit and flow tests (run per PR)
└── README.md
```

### scripts/ Design Principle: Separation of Logic and Side Effects

Internal scripts are separated into two layers to ensure testability.

**Logic layer (`lib/validate.sh`, `lib/prefix.sh`)**: Pure functions with no external command dependencies. Responsible for input validation, prefix resolution, URL construction, etc. Can be unit tested rapidly with bats-core.

**Side-effect layer (`lib/azure.sh`)**: Thin function wrappers around az cli calls such as `az storage blob upload-batch` / `delete-batch`. During testing, these are replaced with mock versions (`tests/helpers/mock_azure.sh`), enabling testing of the entire deploy.sh / cleanup.sh flow without actual Azure connections.

**Entry points (`deploy.sh`, `cleanup.sh`)**: Scripts called from `action.yml`. They combine functions from the logic layer and side-effect layer to execute the processing.

### lib/ Function List

```
validate.sh
├── validate_storage_account()      # Validate account name format
├── validate_action()               # Validate "deploy" or "cleanup"
├── validate_source_dir()           # Check directory existence (for deploy)
├── validate_branch_name()          # Validate branch name format
├── validate_pull_request_number()  # Validate PR number is a positive integer
├── validate_prefix_inputs()        # Validate branch_name / pull_request_number inputs
└── validate_site_name()            # Validate site identifier format (lowercase alphanumeric + hyphens, max 63 chars)

prefix.sh
├── build_blob_prefix()             # Generate Blob prefix from site_name + target_prefix (<site_name>/<target_prefix>)
├── resolve_target_prefix()         # Resolve prefix from branch_name + pull_request_number
├── build_site_url()                # Generate URL from endpoint + prefix (ensures trailing /)
└── build_blob_pattern()            # Generate pattern string for delete-batch
```

**deploy.sh / cleanup.sh**: Read the `INPUT_SITE_NAME` environment variable, concatenate site_name and target_prefix via `build_blob_prefix()`, then pass the result to existing functions. azure.sh treats the concatenated path as an opaque string.

---

## Testing Strategy

**bats-core** (Bash Automated Testing System) is used for testing bash scripts.

| Test Layer | Target | Azure Resources | Execution Timing |
|---|---|---|---|
| Unit tests | lib/ functions | Not required | On PR creation/update (CI automatic) |
| Flow tests | deploy.sh / cleanup.sh (az mocked) | Not required | On PR creation/update (CI automatic) |
| E2E tests | Entire lifecycle | Required | Manual / Pre-release |

**Unit tests**: Test each function in `lib/validate.sh` and `lib/prefix.sh` individually. No external command dependencies, enabling fast execution.

**Flow tests**: Test the entire flow of `deploy.sh` and `cleanup.sh`. Replace az cli functions with mocks via `tests/helpers/mock_azure.sh`, verifying execution order, arguments, and abort-on-error behavior.

**E2E tests**: Use a test repository to verify the entire lifecycle in a real Azure environment. See [`e2e.md`](e2e.md) for details.

For test execution instructions, see [README.md](../README.md).

### Dev Meta-Repository Test Execution Layer (Shared Runner + Adapters)

In the dev meta-repository (`azure-blob-storage-site-deploy-dev`), the test execution entry point is unified under `scripts/test.sh`.

- `unit` / `flow`: Invoke Bats tests in the product repository
- `e2e`: Invoke `scripts/e2e/orchestrator.sh` (prerequisite checks and execution summary are provided by the shared runner)
- `all`: Execute `unit + flow + e2e` sequentially (default)

This architecture maintains the E2E internal implementation (local execution orchestrator) while providing developers with a consistent CLI, prerequisite error handling, and execution summary format.
