#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRODUCT_DIR="${REPO_ROOT}/repos/product"
E2E_DIR="${REPO_ROOT}/repos/e2e"

PRODUCT_BATS_WRAPPER="${PRODUCT_DIR}/tests/bin/bats"
PRODUCT_BATS_INSTALL_SCRIPT="${PRODUCT_DIR}/scripts/install-bats.sh"
PRODUCT_BATS_BIN="${PRODUCT_DIR}/.tools/bin/bats"
E2E_ORCHESTRATOR="${REPO_ROOT}/scripts/e2e/orchestrator.sh"
E2E_VERIFY_SCRIPT="${REPO_ROOT}/scripts/e2e/verify.sh"

readonly EXIT_RUNTIME=1
readonly EXIT_USAGE=2
readonly EXIT_PREFLIGHT=3

CURRENT_PHASE=""
FAILED_PHASE=""
RUN_MODE=""
RUN_STARTED_AT=""

log() {
  printf '[test-runner] %s\n' "$*"
}

log_error() {
  printf '[test-runner] エラー: %s\n' "$*" >&2
}

set_phase() {
  CURRENT_PHASE="$1"
}

die_usage() {
  local message="$1"
  FAILED_PHASE="${CURRENT_PHASE:-usage}"
  log_error "$message"
  if [[ -n "${RUN_MODE}" && -n "${RUN_STARTED_AT}" ]]; then
    print_summary "${RUN_MODE}" "${EXIT_USAGE}" "${RUN_STARTED_AT}"
  fi
  print_usage >&2
  exit "${EXIT_USAGE}"
}

die_preflight() {
  local message="$1"
  FAILED_PHASE="${CURRENT_PHASE:-preflight}"
  log_error "$message"
  if [[ -n "${RUN_MODE}" && -n "${RUN_STARTED_AT}" ]]; then
    print_summary "${RUN_MODE}" "${EXIT_PREFLIGHT}" "${RUN_STARTED_AT}"
  fi
  exit "${EXIT_PREFLIGHT}"
}

print_usage() {
  cat <<'EOF'
使い方: ./scripts/test.sh [unit|flow|all|e2e|check]

  unit   — 単体テスト（bats-core）
  flow   — フローテスト（bats-core / azモック）
  all    — 単体テスト + フローテスト + E2Eテスト（デフォルト）
  e2e    — E2Eテスト（実Azure / gh / jq 必要）
  check  — テスト実行の前提条件を診断（副作用なし）

終了コード:
  0  成功
  1  テスト実行失敗
  2  使い方エラー
  3  前提条件不足
EOF
}

require_path_exists() {
  local path="$1"
  local hint="$2"
  if [[ ! -e "$path" ]]; then
    die_preflight "${hint} (${path})"
  fi
}

require_file_exists() {
  local path="$1"
  local hint="$2"
  if [[ ! -f "$path" ]]; then
    die_preflight "${hint} (${path})"
  fi
}

require_command() {
  local name="$1"
  local hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    die_preflight "${name} が未導入です。${hint}"
  fi
}

require_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    die_preflight "gh CLI にログインしていません（'gh auth login' を実行してください）"
  fi
}

ensure_bats_installed() {
  set_phase "preflight:product-submodule"
  require_path_exists "${PRODUCT_DIR}/.git" "product サブモジュールが初期化されていません。'just init' を実行してください"

  set_phase "preflight:product-bats-install-script"
  require_file_exists "${PRODUCT_BATS_INSTALL_SCRIPT}" "repos/product/scripts/install-bats.sh が見つかりません"

  if [[ ! -f "${PRODUCT_BATS_BIN}" ]]; then
    set_phase "preflight:product-bats-auto-install"
    log "bats-core が未導入です。インストールを実行します..."
    if ! bash "${PRODUCT_BATS_INSTALL_SCRIPT}"; then
      die_preflight "bats-core の自動インストールに失敗しました（'just setup-product' を試してください）"
    fi
  fi

  set_phase "preflight:product-bats-wrapper"
  require_file_exists "${PRODUCT_BATS_WRAPPER}" "product の bats ラッパーが見つかりません"
}

check_unit_flow_preconditions() {
  set_phase "preflight:product-submodule"
  require_path_exists "${PRODUCT_DIR}/.git" "product サブモジュールが初期化されていません。'just init' を実行してください"

  set_phase "preflight:product-bats-install-script"
  require_file_exists "${PRODUCT_BATS_INSTALL_SCRIPT}" "repos/product/scripts/install-bats.sh が見つかりません"

  set_phase "preflight:product-bats"
  if [[ ! -f "${PRODUCT_BATS_BIN}" ]]; then
    die_preflight "bats-core が未導入です（'just setup-product' または './scripts/test.sh unit' を実行してください）"
  fi

  set_phase "preflight:product-bats-wrapper"
  require_file_exists "${PRODUCT_BATS_WRAPPER}" "product の bats ラッパーが見つかりません"
}

check_e2e_preconditions() {
  set_phase "preflight:e2e-submodule"
  require_path_exists "${E2E_DIR}/.git" "e2e サブモジュールが初期化されていません。'just init' を実行してください"

  set_phase "preflight:e2e-orchestrator"
  require_file_exists "${E2E_ORCHESTRATOR}" "E2E オーケストレーターが見つかりません"

  set_phase "preflight:e2e-verify"
  require_file_exists "${E2E_VERIFY_SCRIPT}" "E2E verify スクリプトが見つかりません"

  set_phase "preflight:e2e-gh"
  require_command "gh" "'just setup-tools' を実行してください"

  set_phase "preflight:e2e-jq"
  require_command "jq" "'just setup-tools' を実行してください"

  set_phase "preflight:e2e-gh-auth"
  require_gh_auth
}

print_check_result_ok() {
  printf '[test-runner] OK: %s\n' "$1"
}

print_check_result_ng() {
  printf '[test-runner] NG: %s\n' "$1" >&2
}

run_check() {
  local failed=0

  log "=== check: テスト前提条件診断 ==="

  if [[ -e "${PRODUCT_DIR}/.git" ]]; then
    print_check_result_ok "product サブモジュール (${PRODUCT_DIR}/.git)"
  else
    print_check_result_ng "product サブモジュールが未初期化です（'just init'）"
    failed=1
  fi

  if [[ -e "${E2E_DIR}/.git" ]]; then
    print_check_result_ok "e2e サブモジュール (${E2E_DIR}/.git)"
  else
    print_check_result_ng "e2e サブモジュールが未初期化です（'just init'）"
    failed=1
  fi

  if [[ -f "${PRODUCT_BATS_INSTALL_SCRIPT}" ]]; then
    print_check_result_ok "bats install script (${PRODUCT_BATS_INSTALL_SCRIPT})"
  else
    print_check_result_ng "repos/product/scripts/install-bats.sh が見つかりません"
    failed=1
  fi

  if [[ -f "${PRODUCT_BATS_BIN}" ]]; then
    print_check_result_ok "bats-core (${PRODUCT_BATS_BIN})"
  else
    print_check_result_ng "bats-core が未導入です（'just setup-product' または './scripts/test.sh unit'）"
    failed=1
  fi

  if [[ -f "${E2E_ORCHESTRATOR}" ]]; then
    print_check_result_ok "e2e orchestrator (${E2E_ORCHESTRATOR})"
  else
    print_check_result_ng "scripts/e2e/orchestrator.sh が見つかりません"
    failed=1
  fi

  if [[ -f "${E2E_VERIFY_SCRIPT}" ]]; then
    print_check_result_ok "e2e verify (${E2E_VERIFY_SCRIPT})"
  else
    print_check_result_ng "scripts/e2e/verify.sh が見つかりません"
    failed=1
  fi

  if command -v gh >/dev/null 2>&1; then
    print_check_result_ok "gh"
    if gh auth status >/dev/null 2>&1; then
      print_check_result_ok "gh auth status"
    else
      print_check_result_ng "gh にログインしていません（'gh auth login'）"
      failed=1
    fi
  else
    print_check_result_ng "gh が未導入です（'just setup-tools'）"
    failed=1
  fi

  if command -v jq >/dev/null 2>&1; then
    print_check_result_ok "jq"
  else
    print_check_result_ng "jq が未導入です（'just setup-tools'）"
    failed=1
  fi

  if [[ "${failed}" -ne 0 ]]; then
    FAILED_PHASE="preflight:check"
    log_error "check で未解決の項目があります"
    return "${EXIT_PREFLIGHT}"
  fi

  log "check 完了: すべての前提条件を満たしています。"
  return 0
}

run_unit() {
  set_phase "preflight:unit"
  ensure_bats_installed
  set_phase "run:unit"
  log "=== 単体テスト ==="
  bash "${PRODUCT_BATS_WRAPPER}" "${PRODUCT_DIR}/tests/unit"
}

run_flow() {
  set_phase "preflight:flow"
  ensure_bats_installed
  set_phase "run:flow"
  log "=== フローテスト ==="
  bash "${PRODUCT_BATS_WRAPPER}" "${PRODUCT_DIR}/tests/flow"
}

run_all() {
  set_phase "run:unit"
  run_unit
  echo ""
  set_phase "run:flow"
  run_flow
  echo ""
  set_phase "run:e2e"
  run_e2e
}

run_e2e() {
  set_phase "preflight:e2e"
  check_e2e_preconditions
  set_phase "run:e2e"
  log "=== E2Eテスト ==="
  log "推奨入口: ./scripts/test.sh e2e（下位実装として scripts/e2e/orchestrator.sh を実行）"
  bash "${E2E_ORCHESTRATOR}"
}

print_summary() {
  local mode="$1"
  local code="$2"
  local started_at="$3"
  local ended_at elapsed

  ended_at="$(date +%s)"
  elapsed=$((ended_at - started_at))

  if [[ "${code}" -eq 0 ]]; then
    log "=== summary ==="
    log "mode=${mode} result=success elapsed=${elapsed}s"
    return
  fi

  log_error "=== summary ==="
  if [[ -n "${FAILED_PHASE}" ]]; then
    log_error "mode=${mode} result=failed exit_code=${code} phase=${FAILED_PHASE} elapsed=${elapsed}s"
  else
    log_error "mode=${mode} result=failed exit_code=${code} phase=${CURRENT_PHASE:-unknown} elapsed=${elapsed}s"
  fi
}

run_with_summary() {
  local mode="$1"
  local started_at code
  started_at="$(date +%s)"
  RUN_MODE="${mode}"
  RUN_STARTED_AT="${started_at}"
  FAILED_PHASE=""
  CURRENT_PHASE=""

  if [[ "${mode}" == "check" ]]; then
    if run_check; then
      code=0
    else
      code=$?
    fi
    print_summary "${mode}" "${code}" "${started_at}"
    return "${code}"
  fi

  if run_${mode}; then
    code=0
  else
    code=$?
    if [[ -z "${FAILED_PHASE}" ]]; then
      FAILED_PHASE="${CURRENT_PHASE:-run:${mode}}"
    fi
  fi

  print_summary "${mode}" "${code}" "${started_at}"
  RUN_MODE=""
  RUN_STARTED_AT=""
  return "${code}"
}

main() {
  local command="${1:-all}"

  if [[ $# -gt 1 ]]; then
    die_usage "位置引数は1つまでです"
  fi

  case "${command}" in
    unit|flow|all|e2e|check)
      run_with_summary "${command}"
      ;;
    -h|--help)
      print_usage
      ;;
    *)
      die_usage "不明なコマンド: ${command}"
      ;;
  esac
}

main "$@"
