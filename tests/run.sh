#!/usr/bin/env bash
# Canonical repository test runner. Suites run concurrently with buffered output.

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
JOBS="${TEST_JOBS:-}"
LIST_ONLY=false

usage() {
  printf 'usage: %s [--jobs COUNT] [--list]\n' "${0##*/}"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

readonly TEST_FILES=(
  "$TEST_DIR/contract_test.sh"
  "$TEST_DIR/cli_test.sh"
  "$TEST_DIR/upstream_test.sh"
  "$TEST_DIR/lean_engine_test.sh"
  "$TEST_DIR/host_test.sh"
  "$TEST_DIR/git_test.sh"
  "$TEST_DIR/tools_test.sh"
  "$TEST_DIR/shell_test.sh"
  "$TEST_DIR/tmux_test.sh"
  "$TEST_DIR/nvim_test.sh"
  "$TEST_DIR/agents_test.sh"
  "$TEST_DIR/herdr_test.sh"
  "$TEST_DIR/desktop_test.sh"
  "$TEST_DIR/secrets_test.sh"
  "$TEST_DIR/windows_terminal_test.sh"
)

# Start historically long suites first; reporting remains in canonical order.
readonly RUN_FILES=(
  "$TEST_DIR/shell_test.sh"
  "$TEST_DIR/nvim_test.sh"
  "$TEST_DIR/git_test.sh"
  "$TEST_DIR/tools_test.sh"
  "$TEST_DIR/lean_engine_test.sh"
  "$TEST_DIR/agents_test.sh"
  "$TEST_DIR/tmux_test.sh"
  "$TEST_DIR/upstream_test.sh"
  "$TEST_DIR/herdr_test.sh"
  "$TEST_DIR/desktop_test.sh"
  "$TEST_DIR/secrets_test.sh"
  "$TEST_DIR/host_test.sh"
  "$TEST_DIR/windows_terminal_test.sh"
  "$TEST_DIR/contract_test.sh"
  "$TEST_DIR/cli_test.sh"
)

for test_file in "${TEST_FILES[@]}"; do
  count=0
  for run_file in "${RUN_FILES[@]}"; do
    [[ "$run_file" != "$test_file" ]] || ((count += 1))
  done
  ((count == 1)) || fail "suite must appear exactly once in RUN_FILES: ${test_file##*/}"
done
for run_file in "${RUN_FILES[@]}"; do
  for test_file in "${TEST_FILES[@]}"; do
    [[ "$test_file" != "$run_file" ]] || continue 2
  done
  fail "RUN_FILES contains an unlisted suite: ${run_file##*/}"
done

while (($#)); do
  case "$1" in
    --jobs)
      (($# >= 2)) || fail '--jobs requires a count'
      JOBS="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --list)
      LIST_ONLY=true
      shift
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

if [[ -z "$JOBS" ]]; then
  JOBS="$(nproc 2>/dev/null || printf '1')"
  ((JOBS > 2)) && JOBS=$((JOBS - 1)) || JOBS=1
  ((JOBS <= 4)) || JOBS=4
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || fail '--jobs must be a positive integer'

bash -n "$TEST_DIR/lib/harness.sh" "${TEST_FILES[@]}" || \
  fail 'a test file has invalid Bash syntax'

if [[ "$LIST_ONLY" == true ]]; then
  for test_file in "${TEST_FILES[@]}"; do
    printf '%s\n' "${test_file##*/}"
  done
  exit 0
fi

RUN_ROOT="$(mktemp -d)"
readonly RUN_ROOT
trap 'rm -rf -- "$RUN_ROOT"' EXIT

run_suite() {
  local test_file="$1" name="${1##*/}" start=$SECONDS status
  trap 'exit 130' INT
  trap 'exit 143' TERM
  set +e
  "$test_file" > "$RUN_ROOT/$name.log" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status" > "$RUN_ROOT/$name.status"
  printf '%s\n' "$((SECONDS - start))" > "$RUN_ROOT/$name.seconds"
}

for test_file in "${RUN_FILES[@]}"; do
  while (($(jobs -pr | wc -l) >= JOBS)); do
    wait -n
  done
  run_suite "$test_file" &
done
wait

failed=false
for test_file in "${TEST_FILES[@]}"; do
  name="${test_file##*/}"
  status="$(< "$RUN_ROOT/$name.status")"
  seconds="$(< "$RUN_ROOT/$name.seconds")"
  printf '== %s (%ss)\n' "$name" "$seconds"
  if [[ "$status" == 0 ]]; then
    grep -E '^(PASS|SKIP|WARN):' "$RUN_ROOT/$name.log" || printf 'PASS: %s\n' "$name"
  else
    failed=true
    printf 'FAIL: %s exited with status %s\n' "$name" "$status" >&2
    cat "$RUN_ROOT/$name.log" >&2
  fi
done

[[ "$failed" == false ]] || fail 'one or more repository test suites failed'

printf 'PASS: all repository test suites\n'
