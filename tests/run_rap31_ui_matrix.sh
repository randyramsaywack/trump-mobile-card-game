#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
BASE_TMP="${TMPDIR:-/tmp}/trump-rap31-ui-matrix-$$"
TIMEOUT="${RAP31_TIMEOUT:-180}"
VISIBLE="${RAP31_VISIBLE:-0}"
COUNTS="${RAP31_COUNTS:-2 3 4}"

mkdir -p "$BASE_TMP"

log() {
  printf '[rap31-matrix] %s\n' "$*"
}

cleanup_pids() {
  for pid in "$@"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

run_case() {
  local count="$1"
  local dir="$BASE_TMP/$count"
  local code_file="$dir/room_code.txt"
  local server_log="$dir/server.log"
  local pids=()
  local ok=1

  rm -rf "$dir"
  mkdir -p "$dir/shots"
  case "$count" in
    2) printf 'ABFKMR' >"$code_file" ;;
    3) printf 'CDEGHJ' >"$code_file" ;;
    4) printf 'KLMNPQ' >"$code_file" ;;
    *) printf 'RSTUVW' >"$code_file" ;;
  esac

  log "starting ${count}-human case"
  "$GODOT" --headless --path "$ROOT" --server --log-file "$server_log" >"$dir/server.stdout" 2>&1 &
  local server_pid=$!
  pids+=("$server_pid")
  sleep 1

  for ((i=0; i<count; i++)); do
    local role="join"
    local name="Auto$((i + 1))"
    local done_file="$dir/client_${i}.done"
    local log_file="$dir/client_${i}.log"
    local shot_file="$dir/shots/client_${i}_round_end.png"
    local display_args=("--headless")
    if [[ "$VISIBLE" == "1" ]]; then
      role="$role"
      display_args=("--resolution" "390x844" "--position" "$((40 + i * 420)),80")
    fi
    if [[ "$i" == "0" ]]; then
      role="host"
      name="Host"
    fi

    "$GODOT" "${display_args[@]}" --path "$ROOT" --log-file "$log_file" -- \
      --rap31-auto-client \
      --rap31-role="$role" \
      --rap31-username="$name" \
      --rap31-human-count="$count" \
      --rap31-code-file="$code_file" \
      --rap31-done-file="$done_file" \
      --rap31-shot-file="$shot_file" \
      --rap31-timeout="$TIMEOUT" \
      >"$dir/client_${i}.stdout" 2>&1 &
    pids+=("$!")
    sleep 0.25
  done

  local start
  start="$(date +%s)"
  while true; do
    local done_count=0
    for ((i=0; i<count; i++)); do
      [[ -f "$dir/client_${i}.done" ]] && done_count=$((done_count + 1))
    done
    if [[ "$done_count" == "$count" ]]; then
      break
    fi
    local now
    now="$(date +%s)"
    if (( now - start > TIMEOUT + 15 )); then
      log "${count}-human case timed out waiting for clients"
      ok=0
      break
    fi
    sleep 1
  done

  for ((i=0; i<count; i++)); do
    local done_file="$dir/client_${i}.done"
    if [[ ! -f "$done_file" ]]; then
      log "missing done file for ${count}-human client ${i}"
      ok=0
    elif ! grep -q '^PASS' "$done_file"; then
      log "client ${i} failed:"
      cat "$done_file"
      ok=0
    fi
  done

  cleanup_pids "${pids[@]}"
  wait "$server_pid" 2>/dev/null || true

  if [[ "$ok" == "1" ]]; then
    log "${count}-human case PASS"
    return 0
  fi

  log "${count}-human case FAIL; logs in $dir"
  return 1
}

main() {
  if [[ ! -x "$GODOT" ]]; then
    log "Godot executable not found: $GODOT"
    exit 1
  fi

  local overall=0
  for count in $COUNTS; do
    if ! run_case "$count"; then
      overall=1
    fi
    sleep 1
  done

  log "artifacts: $BASE_TMP"
  exit "$overall"
}

main "$@"
