# scripts/e2e/lib.sh — E2Eオーケストレーター共有ヘルパー関数
# 使い方: source ./scripts/e2e/lib.sh
# 注意: set -euo pipefail は呼び出し元が設定する

log() {
  printf '[orchestrator] %s\n' "$*"
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

gh_json() {
  local method="$1"
  local path="$2"
  shift 2
  gh api --method "$method" "$path" "$@"
}

# deploy.ymlの完了をポーリングで待機する
# 引数: event head_sha not_before label
# 環境変数: REPOSITORY
wait_deploy_workflow() {
  local event="$1"
  local head_sha="$2"
  local not_before="$3"
  local label="$4"

  local runs_json run_id status conclusion html_url attempt

  for (( attempt = 1; attempt <= 120; attempt++ )); do
    runs_json="$(
      gh api \
        "/repos/${REPOSITORY}/actions/workflows/deploy.yml/runs?event=${event}&per_page=50"
    )"

    run_id="$(
      jq -r \
        --arg head_sha "$head_sha" \
        --arg not_before "$not_before" \
        '
          .workflow_runs
          | map(select(.head_sha == $head_sha and .created_at >= $not_before))
          | sort_by(.created_at)
          | (last // empty)
          | .id // empty
        ' \
        <<<"$runs_json"
    )"

    if [[ -z "$run_id" ]]; then
      log "${label}: deploy.yml 実行待機中 (${attempt}/120)"
      sleep 5
      continue
    fi

    status="$(
      jq -r \
        --argjson run_id "$run_id" \
        '.workflow_runs[] | select(.id == $run_id) | .status' \
        <<<"$runs_json"
    )"
    conclusion="$(
      jq -r \
        --argjson run_id "$run_id" \
        '.workflow_runs[] | select(.id == $run_id) | (.conclusion // "")' \
        <<<"$runs_json"
    )"
    html_url="$(
      jq -r \
        --argjson run_id "$run_id" \
        '.workflow_runs[] | select(.id == $run_id) | .html_url' \
        <<<"$runs_json"
    )"

    if [[ "$status" != "completed" ]]; then
      log "${label}: run_id=${run_id} status=${status} 完了待機中"
      sleep 5
      continue
    fi

    if [[ "$conclusion" != "success" ]]; then
      log "${label}: deploy.ymlが失敗しました (run_id=${run_id}, conclusion=${conclusion})"
      log "${label}: ${html_url}"
      return 1
    fi

    log "${label}: deploy.yml成功 (run_id=${run_id})"
    return 0
  done

  log "${label}: deploy.yml完了待機がタイムアウトしました"
  return 1
}
