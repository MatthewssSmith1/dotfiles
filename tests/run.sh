#!/usr/bin/env bash
# Test suite runner: syntax-checks and executes every tests/*_test.sh in order.
# Opt-in gates that need external fixtures (tests/tmux_parser_gate.sh) do not
# match the *_test.sh glob and are run manually; see README.md.

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

shopt -s nullglob
test_files=("$TEST_DIR"/*_test.sh)
shopt -u nullglob
((${#test_files[@]} > 0)) || fail 'no test files found'

bash -n "$TEST_DIR/lib/harness.sh" "$TEST_DIR/tmux_parser_gate.sh" "${test_files[@]}" || \
  fail 'a test file has invalid Bash syntax'

for test_file in "${test_files[@]}"; do
  printf '== %s\n' "${test_file##*/}"
  "$test_file" || fail "${test_file##*/} failed"
done

printf 'PASS: all repository test suites\n'
