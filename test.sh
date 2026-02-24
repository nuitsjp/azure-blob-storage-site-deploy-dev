#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_DIR="${SCRIPT_DIR}/repos/product"
BATS="${PRODUCT_DIR}/tests/bin/bats"
INSTALL_SCRIPT="${PRODUCT_DIR}/scripts/install-bats.sh"

# bats が未導入なら自動インストール
if [[ ! -x "${PRODUCT_DIR}/.tools/bin/bats" ]]; then
  echo "bats-core が未導入です。インストールを実行します..."
  bash "${INSTALL_SCRIPT}"
fi

usage() {
  echo "使い方: $0 [unit|flow|all]"
  echo ""
  echo "  unit  — 単体テスト"
  echo "  flow  — フローテスト"
  echo "  all   — 単体テスト + フローテスト（デフォルト）"
  exit 1
}

run_unit() {
  echo "=== 単体テスト ==="
  bash "${BATS}" "${PRODUCT_DIR}/tests/unit"
}

run_flow() {
  echo "=== フローテスト ==="
  bash "${BATS}" "${PRODUCT_DIR}/tests/flow"
}

COMMAND="${1:-all}"

case "${COMMAND}" in
  unit)
    run_unit
    ;;
  flow)
    run_flow
    ;;
  all)
    run_unit
    echo ""
    run_flow
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "不明なコマンド: ${COMMAND}" >&2
    usage
    ;;
esac
