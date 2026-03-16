#!/usr/bin/env bash
# E2Eオーケストレーター — ローカルからライフサイクル全体を検証する
#
# 前提条件:
#   - gh auth status でログイン済み
#   - git submodule update --init --recursive 済み
#   - jq がインストール済み
#
# 使い方:
#   推奨: ./scripts/test.sh e2e
#   ./scripts/e2e/orchestrator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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
RELEASE_TAGS=()
RELEASE_IDS=()

log "=== E2Eオーケストレーター開始 ==="
log "REPOSITORY: ${REPOSITORY}"
log "BASE_URL: ${BASE_URL}"
log "SITE_NAME: ${SITE_NAME}"
log "TEST_BRANCH: ${TEST_BRANCH}"
log "RUN_TAG: ${RUN_TAG}"

# --- クリーンアップ ---

cleanup() {
  local cleanup_failed=0
  local release_id
  local release_tag

  log "=== クリーンアップ開始 ==="

  for release_id in "${RELEASE_IDS[@]}"; do
    log "後片付け: Release ${release_id} を削除"
    if ! gh_json DELETE "/repos/${REPOSITORY}/releases/${release_id}" >/dev/null 2>&1; then
      log "後片付け: Release ${release_id} の削除はスキップ（既に削除済みの可能性）"
    fi
  done

  for release_tag in "${RELEASE_TAGS[@]}"; do
    log "後片付け: タグ ${release_tag} を削除"
    if ! gh_json DELETE "/repos/${REPOSITORY}/git/refs/tags/${release_tag}" >/dev/null 2>&1; then
      log "後片付け: タグ ${release_tag} の削除はスキップ（既に削除済みの可能性）"
    fi
  done

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

# GitHub Release を作成し、後片付け用の Release ID / タグを記録する。
# 引数: tag_name target_commitish release_name release_body
create_release() {
  local tag_name="$1"
  local target_commitish="$2"
  local release_name="$3"
  local release_body="$4"
  local response
  local release_id

  response="$(
    gh_json POST "/repos/${REPOSITORY}/releases" \
      -f tag_name="$tag_name" \
      -f target_commitish="$target_commitish" \
      -f name="$release_name" \
      -f body="$release_body" \
      -F draft=false \
      -F prerelease=false
  )"
  release_id="$(jq -r '.id' <<<"$response")"

  RELEASE_TAGS+=("$tag_name")
  RELEASE_IDS+=("$release_id")
}

# release-latest 検証用の静的コンテンツを生成する。
# docs/index.html と docs/release.txt を更新する。
write_release_content() {
  local marker="$1"
  local release_text="$2"

  cat > docs/index.html <<EOF
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>${marker}</title>
</head>
<body>
  <h1>${marker}</h1>
</body>
</html>
EOF
  printf '%s\n' "$release_text" > docs/release.txt
}

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

# --- Stage 5: latest release 作成 ---

log ""
log "=== Stage 5: latest release 作成 ==="

release_marker="RELEASE-1-${RUN_TAG}"
write_release_content "$release_marker" "release-1-${RUN_TAG}"
git add docs/index.html docs/release.txt
git commit -m "test: E2Eオーケストレータのlatest release作成 ${RUN_TAG}"
release_created_at="$(now_utc)"
git push origin "$TEST_BRANCH"
release_sha="$(git rev-parse HEAD)"
release_tag="v0.0.0-${RUN_TAG}-1"
create_release "$release_tag" "$release_sha" "E2E Release 1 ${RUN_TAG}" "latest release 検証用 1"

log "latest release 作成完了: tag=${release_tag} sha=${release_sha}"

wait_deploy_workflow "release" "$release_sha" "$release_created_at" "latest release create"
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/release-latest/" \
  200 \
  --require-trailing-slash \
  --contains "$release_marker" \
  --retries 20 \
  --interval 5
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/release-latest/release.txt" \
  200 \
  --contains "release-1-${RUN_TAG}" \
  --retries 20 \
  --interval 5

log "Stage 5 完了"

# --- Stage 6: latest release 更新 ---

log ""
log "=== Stage 6: latest release 更新 ==="

release_updated_marker="RELEASE-2-${RUN_TAG}"
write_release_content "$release_updated_marker" "release-2-${RUN_TAG}"
git add docs/index.html docs/release.txt
git commit -m "test: E2Eオーケストレータのlatest release更新 ${RUN_TAG}"
release_updated_at="$(now_utc)"
git push origin "$TEST_BRANCH"
release_updated_sha="$(git rev-parse HEAD)"
release_updated_tag="v0.0.0-${RUN_TAG}-2"
create_release "$release_updated_tag" "$release_updated_sha" "E2E Release 2 ${RUN_TAG}" "latest release 検証用 2"

log "latest release 更新完了: tag=${release_updated_tag} sha=${release_updated_sha}"

wait_deploy_workflow "release" "$release_updated_sha" "$release_updated_at" "latest release update"
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/release-latest/" \
  200 \
  --require-trailing-slash \
  --contains "$release_updated_marker" \
  --retries 20 \
  --interval 5
"${SCRIPT_DIR}/verify.sh" \
  "${BASE_URL}/${SITE_NAME}/release-latest/release.txt" \
  200 \
  --contains "release-2-${RUN_TAG}" \
  --retries 20 \
  --interval 5

log "Stage 6 完了"

# --- 完了 ---

log ""
log "=== E2Eオーケストレーター: 全ステージ成功 ==="
