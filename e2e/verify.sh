#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULT_RETRIES=10
readonly DEFAULT_INTERVAL=3
readonly DEFAULT_TIMEOUT=10

usage() {
  cat <<'EOF'
使い方:
  e2e/verify.sh <url> <expected_status> [options]

options:
  --contains <text>               レスポンスボディに含まれるべき文字列（複数指定可）
  --require-trailing-slash        URLパスの末尾スラッシュを必須にする
  --retries <count>               リトライ回数（既定: 10）
  --interval <seconds>            リトライ間隔秒（既定: 3）
  --timeout <seconds>             curlのタイムアウト秒（既定: 10）
  -h, --help                      このヘルプを表示
EOF
}

log() {
  printf '[verify] %s\n' "$*" >&2
}

die() {
  log "$*"
  exit 1
}

is_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

validate_trailing_slash() {
  local url="$1"
  local without_fragment="${url%%#*}"
  local without_query="${without_fragment%%\?*}"
  local path="${without_query#*://}"

  path="/${path#*/}"

  if [[ "$path" == "/" ]]; then
    return 0
  fi

  [[ "$path" == */ ]]
}

request_once() {
  local url="$1"
  local timeout="$2"
  local body_file="$3"
  local status_file="$4"

  local http_code
  http_code="$(curl \
    --silent \
    --show-error \
    --location \
    --max-time "$timeout" \
    --output "$body_file" \
    --write-out '%{http_code}' \
    "$url")"
  printf '%s' "$http_code" > "$status_file"
}

main() {
  local -a contains_texts=()
  local require_trailing_slash=false
  local retries="$DEFAULT_RETRIES"
  local interval="$DEFAULT_INTERVAL"
  local timeout="$DEFAULT_TIMEOUT"

  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  local url=""
  local expected_status=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --contains)
        [[ $# -ge 2 ]] || die "--contains には値が必要です"
        contains_texts+=("$2")
        shift 2
        ;;
      --require-trailing-slash)
        require_trailing_slash=true
        shift
        ;;
      --retries)
        [[ $# -ge 2 ]] || die "--retries には値が必要です"
        retries="$2"
        shift 2
        ;;
      --interval)
        [[ $# -ge 2 ]] || die "--interval には値が必要です"
        interval="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 ]] || die "--timeout には値が必要です"
        timeout="$2"
        shift 2
        ;;
      --*)
        die "未対応のオプションです: $1"
        ;;
      *)
        if [[ -z "$url" ]]; then
          url="$1"
        elif [[ -z "$expected_status" ]]; then
          expected_status="$1"
        else
          die "位置引数が多すぎます: $1"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$url" ]] || die "URLを指定してください"
  [[ -n "$expected_status" ]] || die "期待ステータスコードを指定してください"
  [[ "$expected_status" =~ ^[0-9]{3}$ ]] || die "期待ステータスコードは3桁の数値で指定してください"
  is_integer "$retries" || die "--retries は0以上の整数で指定してください"
  is_integer "$timeout" || die "--timeout は0以上の整数で指定してください"
  [[ "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--interval は0以上の数値で指定してください"
  (( retries >= 1 )) || die "--retries は1以上で指定してください"
  (( timeout >= 1 )) || die "--timeout は1以上で指定してください"

  if [[ "$require_trailing_slash" == true ]] && ! validate_trailing_slash "$url"; then
    die "URLの末尾スラッシュが必要です: $url"
  fi

  local body_file status_file err_file
  body_file="$(mktemp)"
  status_file="$(mktemp)"
  err_file="$(mktemp)"
  trap 'rm -f "${body_file:-}" "${status_file:-}" "${err_file:-}"' EXIT

  local attempt actual_status curl_error
  for (( attempt = 1; attempt <= retries; attempt++ )); do
    curl_error=""
    : > "$status_file"
    : > "$err_file"
    if ! request_once "$url" "$timeout" "$body_file" "$status_file" 2>"$err_file"; then
      curl_error="$(<"$err_file")"
      log "試行 ${attempt}/${retries}: curl失敗 (${curl_error})"
    else
      actual_status="$(<"$status_file")"
      if [[ "$actual_status" != "$expected_status" ]]; then
        log "試行 ${attempt}/${retries}: ステータス不一致 (expected=${expected_status}, actual=${actual_status})"
      else
        local missing=false text
        for text in "${contains_texts[@]}"; do
          if ! grep -F --quiet -- "$text" "$body_file"; then
            log "試行 ${attempt}/${retries}: ボディに期待文字列が見つかりません: $text"
            missing=true
            break
          fi
        done

        if [[ "$missing" == false ]]; then
          log "成功: ${url} status=${actual_status}"
          return 0
        fi
      fi
    fi

    if (( attempt < retries )); then
      sleep "$interval"
    fi
  done

  if [[ -f "$status_file" ]]; then
    actual_status="$(<"$status_file")"
    log "最終ステータス: ${actual_status:-unknown}"
  fi
  log "最終レスポンス先頭: $(head -c 200 "$body_file" | tr '\n' ' ' || true)"
  return 1
}

main "$@"
