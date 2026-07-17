#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly UPSTREAM="$REPO_DIR/scripts/upstream"
readonly EXPECTED_COMMIT='6aa2aec1c035d50cfb6871d490cdf9a1169f5ac3'
readonly EXPECTED_BLOB='0f8e979785bb2a451f42cd494517d12eabcd54bf'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

copy_fixture() {
  local destination="$1"

  mkdir -p \
    "$destination/scripts" \
    "$destination/schemas" \
    "$destination/manifests" \
    "$destination/packages/upstream/git/.config/git"
  cp -p "$REPO_DIR/scripts/upstream" "$destination/scripts/upstream"
  cp -p "$REPO_DIR/schemas/source-manifest-v1.schema.json" "$destination/schemas/"
  cp -p "$REPO_DIR/manifests/sources.json" "$destination/manifests/"
  cp -p "$REPO_DIR/packages/upstream/git/.config/git/config" \
    "$destination/packages/upstream/git/.config/git/config"
}

new_fixture() {
  local name="$1"

  FIXTURE="$TEMP_ROOT/$name"
  copy_fixture "$FIXTURE"
}

rewrite_manifest() {
  local fixture="$1"
  local filter="$2"
  local temporary="$fixture/manifests/sources.json.new"

  jq "$filter" "$fixture/manifests/sources.json" > "$temporary"
  mv -- "$temporary" "$fixture/manifests/sources.json"
}

expect_failure() {
  local description="$1"
  local expected="$2"
  local output
  shift 2

  if output="$("$@" 2>&1)"; then
    fail "$description unexpectedly succeeded"
  fi
  [[ "$output" == *"$expected"* ]] || {
    printf '%s\n' "$output" >&2
    fail "$description did not report '$expected'"
  }
}

bash -n "$UPSTREAM" || fail 'scripts/upstream has invalid Bash syntax'
[[ -x "$UPSTREAM" ]] || fail 'scripts/upstream is not executable'
command -v jq >/dev/null 2>&1 || fail 'jq is required for upstream tests'
command -v git >/dev/null 2>&1 || fail 'git is required for upstream tests'

readonly TEMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT

new_fixture 'moved checkout with spaces'
moved_checkout="$FIXTURE"
success_output="$(HOME="$TEMP_ROOT/empty-home" "$moved_checkout/scripts/upstream" verify)" || \
  fail 'verification failed from a moved checkout'
[[ "$success_output" == *"$EXPECTED_COMMIT"* ]] || fail 'verification did not print the commit pin'
[[ "$success_output" == *"$EXPECTED_BLOB"* ]] || fail 'verification did not print the blob pin'
[[ "$success_output" == *'v3.8.3'* ]] || fail 'verification did not print the release pin'

real_git="$(command -v git)"
deny_bin="$TEMP_ROOT/deny-bin"
mkdir "$deny_bin"
cat > "$deny_bin/git" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  clone|fetch|pull|ls-remote|remote) exit 97 ;;
esac
exec "$real_git" "\$@"
EOF
cat > "$deny_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
cat > "$deny_bin/wget" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
chmod +x "$deny_bin/git" "$deny_bin/curl" "$deny_bin/wget"
PATH="$deny_bin:/usr/bin:/bin" "$moved_checkout/scripts/upstream" verify >/dev/null || \
  fail 'offline verification attempted a network-capable command'
if command -v unshare >/dev/null 2>&1 && \
  unshare --user --map-root-user --net true >/dev/null 2>&1; then
  unshare --user --map-root-user --net \
    "$moved_checkout/scripts/upstream" verify >/dev/null || \
    fail 'verification failed with the network namespace denied'
fi

new_fixture 'content-drift'
printf '\ndrift\n' >> "$FIXTURE/packages/upstream/git/.config/git/config"
expect_failure 'content drift' 'snapshot blob drift' "$FIXTURE/scripts/upstream" verify

new_fixture 'malformed-home-gitconfig'
mkdir "$TEMP_ROOT/malformed-home"
printf '[broken\n' > "$TEMP_ROOT/malformed-home/.gitconfig"
HOME="$TEMP_ROOT/malformed-home" "$FIXTURE/scripts/upstream" verify >/dev/null || \
  fail 'offline verification read unrelated user Git configuration'

new_fixture 'manifest-blob-drift'
rewrite_manifest "$FIXTURE" '.sources[0].source.blob = "0000000000000000000000000000000000000000"'
expect_failure 'manifest blob drift' 'snapshot blob drift' "$FIXTURE/scripts/upstream" verify

new_fixture 'mode-drift'
chmod 0755 "$FIXTURE/packages/upstream/git/.config/git/config"
expect_failure 'mode drift' 'snapshot mode drift' "$FIXTURE/scripts/upstream" verify

new_fixture 'malformed-manifest'
printf '{\n' > "$FIXTURE/manifests/sources.json"
expect_failure 'malformed manifest' 'source manifest is malformed' "$FIXTURE/scripts/upstream" verify

new_fixture 'newer-schema-version'
rewrite_manifest "$FIXTURE" '.schema_version = 2'
expect_failure 'newer schema version' 'does not conform to schema version 1' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'malformed-schema'
printf '{\n' > "$FIXTURE/schemas/source-manifest-v1.schema.json"
expect_failure 'malformed schema' 'source manifest schema is malformed' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'unknown-manifest-key'
rewrite_manifest "$FIXTURE" '.unexpected = true'
expect_failure 'unknown manifest key' 'does not conform to schema version 1' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'malicious-destination'
rewrite_manifest "$FIXTURE" '.sources[0].destination.path = "../outside"'
expect_failure 'malicious destination path' 'unsafe home-relative destination path' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'malicious-empty-path-segment'
rewrite_manifest "$FIXTURE" '.sources[0].destination.path = ".config//outside"'
expect_failure 'empty destination path segment' 'unsafe home-relative destination path' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'malicious-source'
rewrite_manifest "$FIXTURE" '.sources[0].source.path = "/etc/passwd"'
expect_failure 'malicious source path' 'unsafe source path' "$FIXTURE/scripts/upstream" verify

new_fixture 'malicious-snapshot'
rewrite_manifest "$FIXTURE" '.sources[0].snapshot = "packages/upstream/../outside"'
expect_failure 'malicious snapshot path' 'unsafe snapshot path' "$FIXTURE/scripts/upstream" verify

new_fixture 'extra-inventory'
printf 'extra\n' > "$FIXTURE/packages/upstream/git/.config/git/extra"
expect_failure 'extra snapshot inventory' 'undeclared snapshot inventory path' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'missing-inventory'
rm -- "$FIXTURE/packages/upstream/git/.config/git/config"
expect_failure 'missing snapshot inventory' 'missing or non-regular snapshot' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'symlink-snapshot'
rm -- "$FIXTURE/packages/upstream/git/.config/git/config"
ln -s /etc/passwd "$FIXTURE/packages/upstream/git/.config/git/config"
expect_failure 'symlink snapshot' 'missing or non-regular snapshot' "$FIXTURE/scripts/upstream" verify

expect_failure 'missing command' 'usage: upstream verify' "$UPSTREAM"
expect_failure 'unknown command' 'usage: upstream verify' "$UPSTREAM" sync
expect_failure 'extra argument' 'usage: upstream verify' "$UPSTREAM" verify extra

printf 'PASS: pinned upstream source verification checks\n'
