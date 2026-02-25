set shell := ["bash", "-euo", "pipefail", "-c"]

# デフォルトは一覧表示（既存スクリプトの入口を見つけやすくする）
default:
  @just --list

# サブモジュール初期化
init:
  git submodule update --init --recursive

# 開発環境セットアップ（CLI導入 + product側テスト依存 + 診断）
setup: init setup-tools setup-product doctor

# 開発に必要なCLI（gh / jq）を導入（brew/apt-get対応）
setup-tools:
  #!/usr/bin/env bash
  set -euo pipefail

  missing=()
  command -v gh >/dev/null 2>&1 || missing+=("gh")
  command -v jq >/dev/null 2>&1 || missing+=("jq")

  if [[ "${#missing[@]}" -eq 0 ]]; then
    echo "gh / jq は導入済みです。"
    exit 0
  fi

  echo "未導入ツール: ${missing[*]}"

  if command -v brew >/dev/null 2>&1; then
    echo "Homebrew で導入します..."
    brew install "${missing[@]}"
    exit 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get で導入します..."
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y "${missing[@]}"
    else
      apt-get update
      apt-get install -y "${missing[@]}"
    fi
    exit 0
  fi

  cat <<'EOF'
  自動導入に対応していない環境です。以下を手動で導入してください。
    - gh (GitHub CLI)
    - jq

  導入後に `just doctor` で状態確認できます。
  EOF
  exit 1

# product リポジトリのテスト依存（bats-core）を準備
setup-product:
  #!/usr/bin/env bash
  set -euo pipefail

  if [[ ! -e "repos/product/.git" ]]; then
    echo "エラー: product サブモジュールが初期化されていません。先に 'just init' を実行してください。" >&2
    exit 1
  fi

  if [[ ! -f "repos/product/scripts/install-bats.sh" ]]; then
    echo "エラー: repos/product/scripts/install-bats.sh が見つかりません。" >&2
    exit 1
  fi

  bash "repos/product/scripts/install-bats.sh"

# 開発環境の前提条件を診断
doctor:
  #!/usr/bin/env bash
  set -euo pipefail

  failed=0

  check_cmd() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
      echo "OK: $name"
    else
      echo "NG: $name が未導入です" >&2
      failed=1
    fi
  }

  check_path() {
    local label="$1"
    local path="$2"
    if [[ -e "$path" ]]; then
      echo "OK: $label ($path)"
    else
      echo "NG: $label が見つかりません ($path)" >&2
      failed=1
    fi
  }

  echo "=== doctor: サブモジュール ==="
  check_path "product サブモジュール" "repos/product/.git"
  check_path "e2e サブモジュール" "repos/e2e/.git"

  echo
  echo "=== doctor: CLI ==="
  check_cmd gh
  check_cmd jq

  echo
  echo "=== doctor: product テスト依存 ==="
  if [[ -f "repos/product/.tools/bin/bats" ]]; then
    echo "OK: bats-core (repos/product/.tools/bin/bats)"
  else
    echo "NG: bats-core が未導入です（'just setup-product' または './scripts/test.sh' を実行）" >&2
    failed=1
  fi

  echo
  echo "=== doctor: gh 認証 ==="
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      echo "OK: gh auth status"
    else
      echo "NG: gh にログインしていません（'gh auth login' を実行）" >&2
      failed=1
    fi
  else
    echo "SKIP: gh 未導入のため認証確認をスキップ"
  fi

  echo
  if [[ "$failed" -eq 0 ]]; then
    echo "doctor 完了: すべての前提条件を満たしています。"
  else
    echo "doctor 完了: 未解決の項目があります。" >&2
    exit 1
  fi

# サブモジュール状態確認
submodule-status:
  git submodule status --recursive

# 各リポジトリの状態確認
status:
  git -C repos/product status
  git -C repos/e2e status

# 各リポジトリのログ確認
log:
  git -C repos/product log --oneline -n 10
  git -C repos/e2e log --oneline -n 10

# テスト（単体 + フロー + E2E）
test:
  ./scripts/test.sh all

test-unit:
  ./scripts/test.sh unit

test-flow:
  ./scripts/test.sh flow

# E2E テスト（共通ランナー経由）
test-e2e:
  ./scripts/test.sh e2e

# テスト前提条件の診断
test-check:
  ./scripts/test.sh check

# E2E テスト（Azure 環境必要 / 互換エイリアス）
e2e:
  ./scripts/test.sh e2e

# リリース（明示バージョン）
release version:
  ./scripts/release.sh {{version}}

# リリース（パッチ自動インクリメント）
release-auto:
  ./scripts/release.sh

# main 直接編集防止のための作業ブランチ作成補助
branch-product name:
  git -C repos/product switch -c {{name}}

branch-e2e name:
  git -C repos/e2e switch -c {{name}}
