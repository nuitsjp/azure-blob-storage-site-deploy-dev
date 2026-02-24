#!/usr/bin/env bash
# E2Eオーケストレーター — ローカルからライフサイクル全体を検証する
#
# 前提条件:
#   - gh auth status でログイン済み
#   - git submodule update --init --recursive 済み
#   - jq がインストール済み
#
# 使い方:
#   ./e2e/orchestrator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
E2E_REPO_DIR="${REPO_ROOT}/repos/e2e"

readonly AZURE_STORAGE_ACCOUNT="rgazstoragesitedeploy"

source "${SCRIPT_DIR}/lib.sh"

# --- 前提条件チェック ---

if ! command -v gh &>/dev/null; then
  log "エラー: gh CLI がインストールされていません"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  log "エラー: gh CLI でログインしていません（gh auth login を実行してください）"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  log "エラー: jq がインストールされていません"
  exit 1
fi

if [[ ! -e "${E2E_REPO_DIR}/.git" ]]; then
  log "エラー: e2eサブモジュールが初期化されていません（git submodule update --init --recursive を実行してください）"
  exit 1
fi

# --- 変数準備 ---

BASE_URL="https://${AZURE_STORAGE_ACCOUNT}.z11.web.core.windows.net"
SITE_NAME="e2e-test"
RUN_TAG="e2e-$(date -u '+%Y%m%d%H%M%S')-$$"
TEST_BRANCH="e2e-orch-${RUN_TAG}"

REPOSITORY="$(git -C "${E2E_REPO_DIR}" remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
export REPOSITORY

PR_NUMBER=""
PR_HEAD_SHA=""
BRANCH_PUSH_DONE=false
PR_CREATED=false
PR_CLOSED=false

log "=== E2Eオーケストレーター開始 ==="
log "REPOSITORY: ${REPOSITORY}"
log "BASE_URL: ${BASE_URL}"
log "SITE_NAME: ${SITE_NAME}"
log "TEST_BRANCH: ${TEST_BRANCH}"
log "RUN_TAG: ${RUN_TAG}"

# --- クリーンアップ ---

cleanup() {
  local cleanup_failed=0

  log "=== クリーンアップ開始 ==="

  # PRクローズ
  if [[ "$PR_CREATED" == true && "$PR_CLOSED" != true && -n "$PR_NUMBER" ]]; then
    log "後片付け: PR #${PR_NUMBER} をクローズ"
    if gh_json PATCH "/repos/${REPOSITORY}/pulls/${PR_NUMBER}" -f state=closed >/dev/null 2>&1; then
      PR_CLOSED=true
    else
      log "後片付け: PRクローズに失敗しました"
      cleanup_failed=1
    fi
  fi

  # ブランチ削除
  if [[ "$BRANCH_PUSH_DONE" == true ]]; then
    log "後片付け: ブランチ ${TEST_BRANCH} を削除"
    if ! gh_json DELETE "/repos/${REPOSITORY}/git/refs/heads/${TEST_BRANCH}" >/dev/null 2>&1; then
      log "後片付け: ブランチ削除はスキップ（既に削除済みの可能性）"
    fi
  fi

  if [[ "$cleanup_failed" -ne 0 ]]; then
    log "後片付けに失敗した項目があります"
  fi

  log "=== クリーンアップ完了 ==="
}

trap cleanup EXIT

# --- Stage 1: Main Push ---

log ""
log "=== Stage 1: Main Push ==="

cd "$E2E_REPO_DIR"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git checkout main
git pull --ff-only origin main

main_marker="MAIN-${RUN_TAG}"
marker_ts="$(now_utc)"
printf '\n<!-- %s -->\n' "$main_marker" >> docs/index.html
git add docs/index.html
git commit -m "test: E2Eオーケストレータのmain更新 ${RUN_TAG}"
git push origin main
main_sha="$(git rev-parse HEAD)"

log "main push完了: sha=${main_sha}"

wait_deploy_workflow "push" "$main_sha" "$marker_ts" "main push"
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/main/" \
  200 \
  --require-trailing-slash \
  --contains "$main_marker" \
  --retries 20 \
  --interval 5

log "Stage 1 完了"

# --- Stage 2: PR作成 ---

log ""
log "=== Stage 2: PR作成 ==="

git checkout -b "$TEST_BRANCH"
pr_open_marker="PR-OPEN-${RUN_TAG}"
cat > docs/index.html <<EOF
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>${pr_open_marker}</title>
</head>
<body>
  <h1>${pr_open_marker}</h1>
  <p>stage=open</p>
</body>
</html>
EOF
printf '%s\n' "obsolete-${RUN_TAG}" > docs/obsolete.txt
git add docs/index.html docs/obsolete.txt
git commit -m "test: E2EオーケストレータのPR作成 ${RUN_TAG}"
git push -u origin "$TEST_BRANCH"
BRANCH_PUSH_DONE=true
PR_HEAD_SHA="$(git rev-parse HEAD)"

pr_title="E2E Orchestrator ${RUN_TAG}"
pr_body="自動E2E検証用PR（${RUN_TAG}）"
pr_created_at="$(now_utc)"
pr_response="$(
  gh_json POST "/repos/${REPOSITORY}/pulls" \
    -f title="$pr_title" \
    -f head="$TEST_BRANCH" \
    -f base=main \
    -f body="$pr_body"
)"
PR_NUMBER="$(jq -r '.number' <<<"$pr_response")"
PR_CREATED=true

log "PR #${PR_NUMBER} 作成完了: sha=${PR_HEAD_SHA}"

wait_deploy_workflow "pull_request" "$PR_HEAD_SHA" "$pr_created_at" "PR open"
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/pr-${PR_NUMBER}/" \
  200 \
  --require-trailing-slash \
  --contains "$pr_open_marker" \
  --retries 20 \
  --interval 5
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/pr-${PR_NUMBER}/obsolete.txt" \
  200 \
  --contains "obsolete-${RUN_TAG}" \
  --retries 20 \
  --interval 5

log "Stage 2 完了"

# --- Stage 3: PR更新 ---

log ""
log "=== Stage 3: PR更新 ==="

pr_updated_marker="PR-UPDATED-${RUN_TAG}"
cat > docs/index.html <<EOF
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>${pr_updated_marker}</title>
</head>
<body>
  <h1>${pr_updated_marker}</h1>
  <p>stage=updated</p>
</body>
</html>
EOF
printf '%s\n' "fresh-${RUN_TAG}" > docs/fresh.txt
git add docs/index.html docs/fresh.txt
git rm -f docs/obsolete.txt
git commit -m "test: E2EオーケストレータのPR更新 ${RUN_TAG}"
pr_updated_at="$(now_utc)"
git push origin "$TEST_BRANCH"
PR_HEAD_SHA="$(git rev-parse HEAD)"

log "PR更新push完了: sha=${PR_HEAD_SHA}"

wait_deploy_workflow "pull_request" "$PR_HEAD_SHA" "$pr_updated_at" "PR update"
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/pr-${PR_NUMBER}/" \
  200 \
  --require-trailing-slash \
  --contains "$pr_updated_marker" \
  --retries 20 \
  --interval 5
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/pr-${PR_NUMBER}/fresh.txt" \
  200 \
  --contains "fresh-${RUN_TAG}" \
  --retries 20 \
  --interval 5
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/pr-${PR_NUMBER}/obsolete.txt" \
  404 \
  --retries 20 \
  --interval 5

log "Stage 3 完了"

# --- Stage 4: PRクローズ ---

log ""
log "=== Stage 4: PRクローズ ==="

pr_closed_at="$(now_utc)"
gh_json PATCH "/repos/${REPOSITORY}/pulls/${PR_NUMBER}" -f state=closed >/dev/null
PR_CLOSED=true

log "PR #${PR_NUMBER} クローズ完了"

wait_deploy_workflow "pull_request" "$PR_HEAD_SHA" "$pr_closed_at" "PR close"
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/pr-${PR_NUMBER}/" \
  404 \
  --require-trailing-slash \
  --retries 20 \
  --interval 5

log "Stage 4 完了"

# --- 完了 ---

log ""
log "=== E2Eオーケストレーター: 全ステージ成功 ==="
