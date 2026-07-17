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
    "$destination/lib" \
    "$destination/packages"
  cp -p "$REPO_DIR/scripts/upstream" "$destination/scripts/upstream"
  cp -p "$REPO_DIR/lib/common.sh" "$destination/lib/common.sh"
  cp -p "$REPO_DIR/schemas/source-manifest-v1.schema.json" "$destination/schemas/"
  cp -p "$REPO_DIR/manifests/sources.json" "$destination/manifests/"
  cp -a "$REPO_DIR/packages/upstream" "$destination/packages/upstream"
}

new_fixture() {
  local name="$1"

  FIXTURE="$TEMP_ROOT/$name"
  copy_fixture "$FIXTURE"
}

rewrite_manifest() {
  local fixture="$1"
  local temporary="$fixture/manifests/sources.json.new"
  shift

  jq "$@" "$fixture/manifests/sources.json" > "$temporary"
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

new_fixture 'framework-markers'
printf 'placeholder\n' > "$FIXTURE/packages/upstream/git/.empty-package"
printf '^/\\.empty-package$\n' > "$FIXTURE/packages/upstream/git/.stow-local-ignore"
"$FIXTURE/scripts/upstream" verify >/dev/null || \
  fail 'top-level framework package markers were not accepted'
printf 'nested\n' > "$FIXTURE/packages/upstream/git/.config/.empty-package"
expect_failure 'nested framework marker' 'undeclared snapshot inventory path' \
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
expect_failure 'incomplete sync command' 'usage: upstream verify | sync --proposal <file>' "$UPSTREAM" sync
expect_failure 'unknown command' 'usage: upstream verify | sync --proposal <file>' "$UPSTREAM" unknown
expect_failure 'extra argument' 'usage: upstream verify | sync --proposal <file>' "$UPSTREAM" verify extra

new_fixture 'append-replay'
append_file="$FIXTURE/packages/upstream/git/.config/git/config"
source_blob="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git hash-object --no-filters -- "$append_file")"
printf 'append-one\nappend-two\n' >> "$append_file"
output_blob="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git hash-object --no-filters -- "$append_file")"
rewrite_manifest "$FIXTURE" --arg source_blob "$source_blob" --arg output_blob "$output_blob" \
  '.sources[0].source.blob = $source_blob |
   .sources[0].transform = {type:"append", appended:"append-one\nappend-two\n", output_blob:$output_blob}'
"$FIXTURE/scripts/upstream" verify >/dev/null || fail 'append transform did not replay'
rewrite_manifest "$FIXTURE" '.sources[0].transform.appended = "append-two\nappend-one\n"'
expect_failure 'append ordering' 'recorded appended bytes' "$FIXTURE/scripts/upstream" verify

new_fixture 'artifact-hash'
mkdir -p "$FIXTURE/packages/upstream/nvim/.config/nvim"
cp -p "$REPO_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json" \
  "$FIXTURE/packages/upstream/nvim/.config/nvim/lazy-lock.json"
rewrite_manifest "$FIXTURE" --arg hash '0bf36c5e91f71bc3659391761b3856ab7dfcaeda8aca6a3de954d9a06e7e28de' '
  .artifacts = [{id:"omarchy-nvim-lazy-lock", release:"omarchy-nvim 2026.6.17-1",
    snapshot:"packages/upstream/nvim/.config/nvim/lazy-lock.json",
    destination:{root:"home", path:".config/nvim/lazy-lock.json", mode:"100644"}, sha256:$hash,
    provenance:{artifact:"fixture", artifact_sha256:("2"*64), build_date:"2026-06-17",
      extracted:"/usr/share/omarchy-nvim/config/lazy-lock.json", trust:"accepted", record:"fixture"}}]'
"$FIXTURE/scripts/upstream" verify >/dev/null || fail 'accepted artifact did not verify'
printf '\ncorrupt\n' >> "$FIXTURE/packages/upstream/nvim/.config/nvim/lazy-lock.json"
expect_failure 'artifact hash drift' 'artifact hash drift' "$FIXTURE/scripts/upstream" verify

new_fixture 'unsafe-overwrite-provenance'
rewrite_manifest "$FIXTURE" '.sources[0].transform = {type:"overwrite", replaces:{
  repository:"https://example.invalid/replaced", commit:"1111111111111111111111111111111111111111",
  path:"../outside", blob:"2222222222222222222222222222222222222222", mode:"100644"}}'
expect_failure 'unsafe overwrite provenance' 'unsafe replaced source path' "$FIXTURE/scripts/upstream" verify

printf 'PASS: pinned upstream source verification checks\n'
