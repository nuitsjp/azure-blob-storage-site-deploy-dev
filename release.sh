#!/usr/bin/env bash
# repos/product のリリーススクリプト
#
# セマンティックバージョニングタグ (vX.Y.Z) とメジャーバージョンタグ (vX) を
# 作成・更新し、GitHub Release を発行する。
#
# 前提条件:
#   - gh auth status でログイン済み
#   - git submodule update --init --recursive 済み
#
# 使い方:
#   ./release.sh [バージョン]
#
# 例:
#   ./release.sh v1.2.3   — 指定バージョンでリリース
#   ./release.sh          — 最新タグからパッチバージョンを自動インクリメント

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_DIR="${SCRIPT_DIR}/repos/product"

# --- ヘルパー関数 ---

usage() {
  cat <<EOF
使い方: $0 [バージョン]

  バージョン指定あり:
    $0 v1.2.3   — 指定バージョンでリリース

  バージョン指定なし:
    $0          — 最新タグからパッチバージョンを自動インクリメント

オプション:
  -h, --help    このヘルプを表示
EOF
  exit 0
}

# vX.Y.Z 形式を検証する
validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "エラー: バージョンは vX.Y.Z 形式で指定してください（例: v1.2.3）" >&2
    exit 1
  fi
}

# repos/product の最新 semver タグを取得する
get_latest_tag() {
  git -C "$PRODUCT_DIR" tag -l 'v*.*.*' --sort=-v:refname | head -1
}

# パッチバージョンをインクリメントする（v1.2.3 → v1.2.4）
increment_patch() {
  local version="$1"
  local major minor patch
  major="$(echo "$version" | sed -E 's/^v([0-9]+)\..*/\1/')"
  minor="$(echo "$version" | sed -E 's/^v[0-9]+\.([0-9]+)\..*/\1/')"
  patch="$(echo "$version" | sed -E 's/^v[0-9]+\.[0-9]+\.([0-9]+)$/\1/')"
  echo "v${major}.${minor}.$((patch + 1))"
}

# vX.Y.Z → vX を抽出する
extract_major() {
  local version="$1"
  echo "$version" | sed -E 's/^(v[0-9]+)\..*/\1/'
}

# --- 前提条件チェック ---

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

if ! command -v gh &>/dev/null; then
  echo "エラー: gh CLI がインストールされていません" >&2
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "エラー: gh CLI でログインしていません（gh auth login を実行してください）" >&2
  exit 1
fi

if [[ ! -e "${PRODUCT_DIR}/.git" ]]; then
  echo "エラー: product サブモジュールが初期化されていません（git submodule update --init --recursive を実行してください）" >&2
  exit 1
fi

# --- バージョン決定 ---

if [[ -n "${1:-}" ]]; then
  VERSION="$1"
  validate_version "$VERSION"
else
  LATEST_TAG="$(get_latest_tag)"
  if [[ -z "$LATEST_TAG" ]]; then
    echo "エラー: 既存のタグが見つかりません。初回リリースはバージョンを明示的に指定してください（例: ./release.sh v1.0.0）" >&2
    exit 1
  fi
  VERSION="$(increment_patch "$LATEST_TAG")"
  echo "最新タグ: ${LATEST_TAG} → 新バージョン: ${VERSION}"
fi

MAJOR_TAG="$(extract_major "$VERSION")"
HEAD_SHA="$(git -C "$PRODUCT_DIR" rev-parse --short HEAD)"
FULL_SHA="$(git -C "$PRODUCT_DIR" rev-parse HEAD)"

# リモートリポジトリを取得
REMOTE_URL="$(git -C "$PRODUCT_DIR" remote get-url origin)"
REPO_SLUG="$(echo "$REMOTE_URL" | sed -E 's#.*github\.com[:/]##; s#\.git$##')"

# --- 確認表示 ---

echo ""
echo "=== リリース内容 ==="
echo "  バージョン:       ${VERSION}"
echo "  メジャータグ:     ${MAJOR_TAG}"
echo "  対象コミット:     ${HEAD_SHA}"
echo "  リポジトリ:       ${REPO_SLUG}"
echo ""

# 前回タグからの変更差分を表示
LATEST_TAG="$(get_latest_tag)"
if [[ -n "$LATEST_TAG" ]]; then
  echo "--- ${LATEST_TAG} からの変更 ---"
  git -C "$PRODUCT_DIR" log --oneline "${LATEST_TAG}..HEAD"
  echo ""
fi

read -r -p "リリースを実行しますか？ [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "中断しました。"
  exit 0
fi

# --- タグ作成・プッシュ ---

echo ""
echo "=== タグ作成 ==="

# セマンティックバージョニングタグを作成
echo "タグ ${VERSION} を作成..."
git -C "$PRODUCT_DIR" tag -a "$VERSION" -m "Release ${VERSION}" "$FULL_SHA"

# メジャーバージョンタグを移動（force update）
echo "メジャータグ ${MAJOR_TAG} を更新..."
git -C "$PRODUCT_DIR" tag -f "$MAJOR_TAG" "$FULL_SHA"

# タグをプッシュ
echo "タグをプッシュ..."
git -C "$PRODUCT_DIR" push origin "refs/tags/${VERSION}"
git -C "$PRODUCT_DIR" push origin --force "refs/tags/${MAJOR_TAG}"

echo "タグのプッシュ完了"

# --- GitHub Release 作成 ---

echo ""
echo "=== GitHub Release 作成 ==="

gh release create "$VERSION" \
  --repo "$REPO_SLUG" \
  --generate-notes \
  --latest

echo ""
echo "=== リリース完了 ==="
echo "  ${VERSION}: https://github.com/${REPO_SLUG}/releases/tag/${VERSION}"
