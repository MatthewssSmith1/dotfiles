#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly UPSTREAM="$REPO_DIR/scripts/upstream"
readonly EXPECTED_COMMIT='6aa2aec1c035d50cfb6871d490cdf9a1169f5ac3'
readonly EXPECTED_BLOB='0f8e979785bb2a451f42cd494517d12eabcd54bf'
readonly NVIM_EVIDENCE_REL='docs/omarchy-alignment/artifacts/omarchy-nvim-2026.6.17-1'
readonly NVIM_EVIDENCE="$REPO_DIR/$NVIM_EVIDENCE_REL"
readonly STABLE_DB_SHA256='3ea5428b2ec4109cbd634026c3f88d1103a135e93bcffa658a99e21aedff5289'
readonly PACKAGE_SHA256='b4a6704df33709e4265cab31d2b8e725fa0dc49cd0872ce22b208a13b0f4e67a'
readonly SIGNATURE_SHA256='a88bda5a1dadab3617655a122cc697d50a5601cd5f010e5f33bf0420c8ef43d0'
readonly BASH_REFERENCE_ROOT='packages/upstream/reference/omarchy/default/bash'
readonly BASH_PAYLOAD_ROOT='packages/upstream/bash/.config/dotfiles/upstream/bash'
readonly BASH_MAPPINGS=(
  'shell|shell'
  'aliases|aliases'
  'fns/tmux|fns/tmux'
  'inputrc|inputrc'
)

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
    "$destination/packages" \
    "$destination/docs/omarchy-alignment/artifacts"
  cp -p "$REPO_DIR/scripts/upstream" "$destination/scripts/upstream"
  cp -p "$REPO_DIR/lib/common.sh" "$destination/lib/common.sh"
  cp -p "$REPO_DIR/schemas/source-manifest-v1.schema.json" "$destination/schemas/"
  cp -p "$REPO_DIR/manifests/sources.json" "$destination/manifests/"
  cp -a "$REPO_DIR/packages/upstream" "$destination/packages/upstream"
  cp -a "$NVIM_EVIDENCE" "$destination/docs/omarchy-alignment/artifacts/"
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

for evidence_file in README.md SHA256SUMS package.sig.b64 omarchy-signing-key.asc \
  repository.desc .PKGINFO .BUILDINFO retrieval.txt config.sha256; do
  [[ -f "$NVIM_EVIDENCE/$evidence_file" && ! -L "$NVIM_EVIDENCE/$evidence_file" ]] || \
    fail "missing regular Neovim artifact evidence: $evidence_file"
done
grep -Fx "$STABLE_DB_SHA256  omarchy.db" "$NVIM_EVIDENCE/SHA256SUMS" >/dev/null || \
  fail 'stable repository database checksum evidence drifted'
grep -Fx "$PACKAGE_SHA256  omarchy-nvim-2026.6.17-1-any.pkg.tar.zst" \
  "$NVIM_EVIDENCE/SHA256SUMS" >/dev/null || fail 'stable package checksum evidence drifted'
grep -Fx "$SIGNATURE_SHA256  omarchy-nvim-2026.6.17-1-any.pkg.tar.zst.sig" \
  "$NVIM_EVIDENCE/SHA256SUMS" >/dev/null || fail 'stable package signature checksum evidence drifted'
[[ "$(base64 -d "$NVIM_EVIDENCE/package.sig.b64" | sha256sum | cut -d' ' -f1)" == \
  "$SIGNATURE_SHA256" ]] || fail 'preserved detached signature bytes drifted'
[[ "$(sha256sum "$NVIM_EVIDENCE/omarchy-signing-key.asc" | cut -d' ' -f1)" == \
  '15d6aac44df688165b2ea35fe0b23af239bbc66a6909c10a5c219e8d94b707de' ]] || \
  fail 'preserved Omarchy signing key drifted'
grep -Fx 'pkgver = 2026.6.17-1' "$NVIM_EVIDENCE/.PKGINFO" >/dev/null || \
  fail 'preserved package identity drifted'
grep -Fx 'pkgbuild_sha256sum = 92bbc655801be780fddcf04144c60fdcac7ec74572488024dec25257b65ed491' \
  "$NVIM_EVIDENCE/.BUILDINFO" >/dev/null || fail 'preserved PKGBUILD identity drifted'
grep -Fx '%VERSION%' "$NVIM_EVIDENCE/repository.desc" >/dev/null || \
  fail 'stable repository package record is malformed'

snapshot_hashes="$TEMP_ROOT/committed-nvim-config.sha256"
while IFS= read -r snapshot; do
  relative="${snapshot#packages/upstream/nvim/.config/nvim/}"
  if jq -e --arg snapshot "$snapshot" '
    any(.sources[]; .snapshot == $snapshot and
      ((.transform | type) == "object" and .transform.type == "stage8-nvim-policy-v1"))
  ' "$REPO_DIR/manifests/sources.json" >/dev/null; then
    grep -E "^[0-9a-f]{64}  ${relative//./\\.}$" "$NVIM_EVIDENCE/config.sha256"
  else
    printf '%s  %s\n' "$(sha256sum "$REPO_DIR/$snapshot" | cut -d' ' -f1)" "$relative"
  fi
done < <(jq -r '
  ([.sources[] | select(.snapshot | startswith("packages/upstream/nvim/.config/nvim/")) | .snapshot] +
   [(.artifacts // [])[] | select(.snapshot | startswith("packages/upstream/nvim/.config/nvim/")) | .snapshot])
  | sort[]
' "$REPO_DIR/manifests/sources.json") > "$snapshot_hashes"
cmp -s "$snapshot_hashes" "$NVIM_EVIDENCE/config.sha256" || \
  fail 'committed Neovim snapshot differs from the signed-package extraction record'
jq -e '
  .artifacts == [{
    id: "omarchy-nvim-lazy-lock",
    release: "omarchy-nvim 2026.6.17-1",
    snapshot: "packages/upstream/nvim/.config/nvim/lazy-lock.json",
    destination: {root: "home", path: ".config/nvim/lazy-lock.json", mode: "100644"},
    sha256: "0bf36c5e91f71bc3659391761b3856ab7dfcaeda8aca6a3de954d9a06e7e28de",
    provenance: {
      artifact: "omarchy-nvim-2026.6.17-1-any.pkg.tar.zst",
      artifact_sha256: "b4a6704df33709e4265cab31d2b8e725fa0dc49cd0872ce22b208a13b0f4e67a",
      build_date: "2026-06-20T19:46:26Z",
      extracted: "2026-07-20; full packaged config matched committed snapshot",
      trust: "verified signed stable package; archive omitted due size",
      record: "docs/omarchy-alignment/artifacts/omarchy-nvim-2026.6.17-1/README.md"
    }
  }]
' "$REPO_DIR/manifests/sources.json" >/dev/null || fail 'accepted stable artifact provenance drifted'
jq -e '
  [.pins[] | [.id, .commit, (.package_identity // "-")]] == [
    ["omarchy", "6aa2aec1c035d50cfb6871d490cdf9a1169f5ac3", "-"],
    ["lazyvim-starter", "803bc181d7c0d6d5eeba9274d9be49b287294d99", "omarchy-nvim 2026.6.17-1"],
    ["omarchy-pkgs", "78e5cc81953c44c804eb00e5be093e2674e09503", "omarchy-nvim 2026.6.17-1"]
  ]
' "$REPO_DIR/manifests/proposals/2026-07-20-stage8-neovim-stable.json" >/dev/null || \
  fail 'Stage 8 stable reevaluation proposal drifted'

new_fixture 'moved checkout with spaces'
moved_checkout="$FIXTURE"
success_output="$(HOME="$TEMP_ROOT/empty-home" "$moved_checkout/scripts/upstream" verify)" || \
  fail 'verification failed from a moved checkout'
[[ "$success_output" == *"$EXPECTED_COMMIT"* ]] || fail 'verification did not print the commit pin'
[[ "$success_output" == *"$EXPECTED_BLOB"* ]] || fail 'verification did not print the blob pin'
[[ "$success_output" == *'v3.8.3'* ]] || fail 'verification did not print the release pin'

for mapping in "${BASH_MAPPINGS[@]}"; do
  IFS='|' read -r reference payload <<< "$mapping"
  cmp -s "$moved_checkout/$BASH_REFERENCE_ROOT/$reference" \
    "$moved_checkout/$BASH_PAYLOAD_ROOT/$payload" || \
    fail "deployable Bash payload differs from its pinned reference: $payload"
done
jq -e '
  [
    .sources[] |
    select(.snapshot | startswith("packages/upstream/bash/")) |
    [.source.path, .destination.path]
  ] == [
    ["default/bash/shell", ".config/dotfiles/upstream/bash/shell"],
    ["default/bash/aliases", ".config/dotfiles/upstream/bash/aliases"],
    ["default/bash/fns/tmux", ".config/dotfiles/upstream/bash/fns/tmux"],
    ["default/bash/inputrc", ".config/dotfiles/upstream/bash/inputrc"]
  ]
' "$moved_checkout/manifests/sources.json" >/dev/null || \
  fail 'deployable Bash manifest inventory is not the selected four-source mapping'
for excluded in completions envs functions init rc fns/compression fns/drives \
  fns/ssh-port-forwarding fns/transcoding fns/worktrees; do
  [[ ! -e "$moved_checkout/$BASH_PAYLOAD_ROOT/$excluded" && \
    ! -L "$moved_checkout/$BASH_PAYLOAD_ROOT/$excluded" ]] || \
    fail "excluded Bash source was materialized: $excluded"
done

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

new_fixture 'artifact-evidence-drift'
printf 'drift\n' >> "$FIXTURE/$NVIM_EVIDENCE_REL/config.sha256"
expect_failure 'artifact evidence drift' \
  'committed Neovim snapshot differs from the signed-package extraction record' \
  "$FIXTURE/scripts/upstream" verify

new_fixture 'bash-reference-drift'
printf '\ndrift\n' >> "$FIXTURE/$BASH_REFERENCE_ROOT/shell"
expect_failure 'Bash reference drift' 'snapshot blob drift' "$FIXTURE/scripts/upstream" verify

new_fixture 'bash-payload-drift'
printf '\ndrift\n' >> "$FIXTURE/$BASH_PAYLOAD_ROOT/shell"
expect_failure 'Bash payload drift' 'snapshot blob drift' "$FIXTURE/scripts/upstream" verify

new_fixture 'bash-copy-provenance-drift'
rewrite_manifest "$FIXTURE" \
  '(.sources[] | select(.id == "omarchy-bash-deployable-shell").release) = "other"'
expect_failure 'Bash copy provenance drift' 'deployable Bash source mapping is invalid' \
  "$FIXTURE/scripts/upstream" verify

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

new_fixture 'unmanifested-bash-payload'
printf 'excluded\n' > "$FIXTURE/$BASH_PAYLOAD_ROOT/completions"
expect_failure 'unmanifested Bash payload' 'undeclared snapshot inventory path' \
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
