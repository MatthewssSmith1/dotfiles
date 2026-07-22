#!/usr/bin/env bash
# scripts/upstream verify and sync: pinned provenance, drift detection, and
# offline transactional synchronization.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

# The original upstream tests rooted every fixture at TEMP_ROOT; alias it to
# the harness TEST_ROOT so their bodies remain unchanged.
readonly TEMP_ROOT="$TEST_ROOT"

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
readonly LOCK_SOURCE="$REPO_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json"
readonly LOCK_SHA256='0bf36c5e91f71bc3659391761b3856ab7dfcaeda8aca6a3de954d9a06e7e28de'

# Local override: these tests exercise arbitrary commands (scripts/upstream,
# sync_checkout) with a description argument, unlike the harness expect_failure
# that drives bootstrap captures.
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

# Verify fixtures copy only the files scripts/upstream verify reads, so each
# test may corrupt them independently.
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

# Sync fixtures: local file:// remotes, a seeded active checkout, and proposal
# helpers for scripts/upstream sync.
write_file() {
  local path="$1" content="$2" mode="${3:-0644}"
  mkdir -p -- "${path%/*}"
  printf '%s' "$content" > "$path"
  chmod "$mode" -- "$path"
}

commit_repo() {
  local repo="$1" message="$2"
  git -C "$repo" add -A
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
    commit --quiet -m "$message"
  git -C "$repo" rev-parse HEAD
}

make_repositories() {
  local root="$1"
  OMARCHY_REPO="$root/remotes/omarchy"
  STARTER_REPO="$root/remotes/starter"
  PKGS_REPO="$root/remotes/omarchy-pkgs"
  mkdir -p -- "$OMARCHY_REPO" "$STARTER_REPO" "$PKGS_REPO"
  git init --quiet "$OMARCHY_REPO"
  git init --quiet "$STARTER_REPO"
  git init --quiet "$PKGS_REPO"

  write_file "$OMARCHY_REPO/config/git/config" $'[fixture]\n\tsource = omarchy\n'
  write_file "$OMARCHY_REPO/config/tmux/tmux.conf" $'set -g status off\n'
  write_file "$OMARCHY_REPO/config/starship.toml" $'format = "$directory"\n'
  write_file "$OMARCHY_REPO/themes/tokyo-night/neovim.lua" $'return { background = "dark" }\n'
  write_file "$OMARCHY_REPO/default/bash/shell" $'shopt -s histappend\n'
  write_file "$OMARCHY_REPO/default/bash/aliases" $'alias g=git\n'
  write_file "$OMARCHY_REPO/default/bash/fns/tmux" $'tdl() { :; }\n'
  write_file "$OMARCHY_REPO/default/bash/inputrc" $'set completion-ignore-case on\n'
  write_file "$OMARCHY_REPO/default/bash/env" $'export FIXTURE_ENV=1\n'
  write_file "$OMARCHY_REPO/default/bash/bin/fixture-tool" $'#!/usr/bin/env bash\nprintf "fixture\\n"\n' 0755
  OMARCHY_COMMIT="$(commit_repo "$OMARCHY_REPO" 'omarchy fixture')"

  write_file "$STARTER_REPO/init.lua" $'require("config.lazy")\n'
  write_file "$STARTER_REPO/lua/config/options.lua" $'vim.opt.number = true\n'
  write_file "$STARTER_REPO/lua/config/keymaps.lua" $'vim.keymap.set("n", "x", "y")\n'
  write_file "$STARTER_REPO/lua/config/lazy.lua" $'return {}\n'
  write_file "$STARTER_REPO/plugin/starter.lua" $'vim.g.starter = true\n'
  STARTER_COMMIT="$(commit_repo "$STARTER_REPO" 'starter fixture')"

  write_file "$PKGS_REPO/pkgbuilds/omarchy-nvim/lua/config/keymaps.lua" $'vim.keymap.set("n", "x", "overlay")\n'
  write_file "$PKGS_REPO/pkgbuilds/omarchy-nvim/lua/config/remote_clipboard.lua" $'return { setup = function() end }\n'
  write_file "$PKGS_REPO/pkgbuilds/omarchy-nvim/plugin/overlay.lua" $'vim.g.overlay = true\n'
  write_file "$PKGS_REPO/pkgbuilds/omarchy-nvim/lazyvim.json" $'{"extras":[]}\n'
  PKGS_COMMIT="$(commit_repo "$PKGS_REPO" 'package overlay fixture')"

  GIT_INSTEADOF="https://github.com/basecamp/omarchy=file://$OMARCHY_REPO;https://github.com/LazyVim/starter=file://$STARTER_REPO;https://github.com/omacom-io/omarchy-pkgs=file://$PKGS_REPO"
}

seed_active_checkout() {
  local checkout="$1" blob
  mkdir -p -- "$checkout/scripts" "$checkout/lib" "$checkout/schemas" \
    "$checkout/manifests" "$checkout/packages/upstream/git/.config/git" \
    "$checkout/packages/upstream/nvim/.config/nvim"
  cp -p "$REPO_DIR/scripts/upstream" "$checkout/scripts/upstream"
  cp -p "$REPO_DIR/lib/common.sh" "$checkout/lib/common.sh"
  cp -p "$REPO_DIR/schemas/source-manifest-v1.schema.json" "$checkout/schemas/"
  cp -p "$LOCK_SOURCE" "$checkout/packages/upstream/nvim/.config/nvim/lazy-lock.json"
  printf 'active baseline\n' > "$checkout/packages/upstream/git/.config/git/config"
  blob="$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git hash-object --no-filters -- "$checkout/packages/upstream/git/.config/git/config")"
  jq -n --arg blob "$blob" --arg lock_hash "$LOCK_SHA256" '
    {"$schema":"../schemas/source-manifest-v1.schema.json", schema_version:1,
     snapshot_root:"packages/upstream", sources:[{
       id:"active-baseline", repository:"https://example.invalid/active", release:"fixture",
       commit:"1111111111111111111111111111111111111111",
       source:{path:"config", blob:$blob, mode:"100644"},
       snapshot:"packages/upstream/git/.config/git/config",
       destination:{root:"home", path:".config/git/config", mode:"100644"}, transform:"none"
     }], artifacts:[{
       id:"omarchy-nvim-lazy-lock", release:"omarchy-nvim 2026.6.17-1",
       snapshot:"packages/upstream/nvim/.config/nvim/lazy-lock.json",
       destination:{root:"home", path:".config/nvim/lazy-lock.json", mode:"100644"},
       sha256:$lock_hash, provenance:{artifact:"fixture package", artifact_sha256:("2"*64),
         build_date:"2026-06-17", extracted:"/usr/share/omarchy-nvim/config/lazy-lock.json",
         trust:"accepted fixture", record:"docs/omarchy-alignment/artifacts/README.md"}
     }]}
  ' > "$checkout/manifests/sources.json"
}

write_proposal() {
  local path="$1" omarchy="${2:-$OMARCHY_COMMIT}" starter="${3:-$STARTER_COMMIT}" pkgs="${4:-$PKGS_COMMIT}"
  jq -n --arg omarchy "$omarchy" --arg starter "$starter" --arg pkgs "$pkgs" '
    {schema_version:1, pins:[
      {id:"omarchy", repository:"https://github.com/basecamp/omarchy", version:"v-fixture", commit:$omarchy},
      {id:"lazyvim-starter", repository:"https://github.com/LazyVim/starter", version:"fixture", commit:$starter,
       package_identity:"lazyvim-starter fixture-1"},
      {id:"omarchy-pkgs", repository:"https://github.com/omacom-io/omarchy-pkgs", version:"fixture", commit:$pkgs,
       package_identity:"omarchy-nvim fixture-1"}
    ]}
  ' > "$path"
}

sync_checkout() {
  local checkout="$1" proposal="$2"
  shift 2
  env DOTFILES_TESTING=1 DOTFILES_TEST_GIT_INSTEADOF="$GIT_INSTEADOF" "$@" \
    "$checkout/scripts/upstream" sync --proposal "$proposal"
}

fingerprint_active() {
  local checkout="$1"
  (cd "$checkout" && tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 \
    --numeric-owner -cf - packages/upstream manifests/sources.json) | sha256sum | cut -d' ' -f1
}

assert_no_staging() {
  local checkout="$1"
  local paths=("$checkout"/.upstream-staging.*)
  ((${#paths[@]} == 1)) && [[ "${paths[0]}" == "$checkout/.upstream-staging.*" ]] || \
    fail "sync left staging residue in $checkout"
}

# ============================ scripts/upstream verify ============================

# Runtime prerequisites for the verify and sync sections.
[[ -x "$UPSTREAM" ]] || fail 'scripts/upstream is not executable'
command -v jq >/dev/null 2>&1 || fail 'jq is required for upstream tests'
command -v git >/dev/null 2>&1 || fail 'git is required for upstream tests'

# Preserved Neovim artifact evidence is regular, complete, and byte-stable.
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

# The committed Neovim snapshot matches the signed-package extraction record,
# and the accepted artifact and Stage 8 proposal provenance are unchanged.
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

# Verification succeeds from a moved checkout with spaces and prints its pins.
new_fixture 'moved checkout with spaces'
moved_checkout="$FIXTURE"
success_output="$(HOME="$TEMP_ROOT/empty-home" "$moved_checkout/scripts/upstream" verify)" || \
  fail 'verification failed from a moved checkout'
[[ "$success_output" == *"$EXPECTED_COMMIT"* ]] || fail 'verification did not print the commit pin'
[[ "$success_output" == *"$EXPECTED_BLOB"* ]] || fail 'verification did not print the blob pin'
[[ "$success_output" == *'v3.8.3'* ]] || fail 'verification did not print the release pin'

# The deployable Bash payload matches its pinned reference and manifest
# mapping, and excluded sources are never materialized.
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

# Offline verification never invokes a network-capable command, and still
# succeeds with the network namespace denied.
deny_home="$(new_home upstream-deny)"
install_network_sentinels "$deny_home" with-git
HOME="$deny_home" PATH="$deny_home/fake-bin:/usr/bin:/bin" \
  "$moved_checkout/scripts/upstream" verify >/dev/null || \
  fail 'offline verification attempted a network-capable command'
if network_namespace_available; then
  run_network_isolated "$moved_checkout/scripts/upstream" verify >/dev/null || \
    fail 'verification failed with the network namespace denied'
fi

# Content, evidence, payload, and provenance drift are each detected.
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

# Verification ignores unrelated user Git configuration.
new_fixture 'malformed-home-gitconfig'
mkdir "$TEMP_ROOT/malformed-home"
printf '[broken\n' > "$TEMP_ROOT/malformed-home/.gitconfig"
HOME="$TEMP_ROOT/malformed-home" "$FIXTURE/scripts/upstream" verify >/dev/null || \
  fail 'offline verification read unrelated user Git configuration'

# Manifest, schema, and path-safety corruption is refused.
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

# Snapshot inventory is exact: no extra, unmanifested, missing, or symlinked entries.
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

# Command-line usage errors are reported.
expect_failure 'missing command' 'usage: upstream verify' "$UPSTREAM"
expect_failure 'incomplete sync command' 'usage: upstream verify | sync --proposal <file>' "$UPSTREAM" sync
expect_failure 'unknown command' 'usage: upstream verify | sync --proposal <file>' "$UPSTREAM" unknown
expect_failure 'extra argument' 'usage: upstream verify | sync --proposal <file>' "$UPSTREAM" verify extra

# Append transforms replay exactly, including recorded byte ordering.
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

# Accepted artifacts verify by hash and detect drift.
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

# Overwrite transforms with unsafe replaced provenance are refused.
new_fixture 'unsafe-overwrite-provenance'
rewrite_manifest "$FIXTURE" '.sources[0].transform = {type:"overwrite", replaces:{
  repository:"https://example.invalid/replaced", commit:"1111111111111111111111111111111111111111",
  path:"../outside", blob:"2222222222222222222222222222222222222222", mode:"100644"}}'
expect_failure 'unsafe overwrite provenance' 'unsafe replaced source path' "$FIXTURE/scripts/upstream" verify

printf 'PASS: pinned upstream source verification checks\n'

# ============================= scripts/upstream sync =============================

# The fixture lazy-lock must match the accepted artifact constant.
[[ "$(sha256sum "$LOCK_SOURCE" | cut -d' ' -f1)" == "$LOCK_SHA256" ]] || fail 'fixture lazy-lock does not match the accepted constant'

make_repositories "$TEMP_ROOT"
BASE="$TEMP_ROOT/base"
seed_active_checkout "$BASE"
PROPOSAL="$TEMP_ROOT/proposal.json"
write_proposal "$PROPOSAL"

# Malformed, version-only, unknown, missing, and non-HTTPS proposals are refused.
printf '{\n' > "$TEMP_ROOT/malformed.json"
expect_failure 'malformed proposal' 'source proposal is malformed' \
  sync_checkout "$BASE" "$TEMP_ROOT/malformed.json"
jq '.pins[0].commit = "v-fixture"' "$PROPOSAL" > "$TEMP_ROOT/version-only.json"
expect_failure 'version-only proposal' 'version-only inputs are refused' \
  sync_checkout "$BASE" "$TEMP_ROOT/version-only.json"
jq '.pins[0].id = "unknown"' "$PROPOSAL" > "$TEMP_ROOT/unknown.json"
expect_failure 'unknown proposal pin' "unknown proposal pin 'unknown'" \
  sync_checkout "$BASE" "$TEMP_ROOT/unknown.json"
jq 'del(.pins[2])' "$PROPOSAL" > "$TEMP_ROOT/missing.json"
expect_failure 'missing proposal pin' "missing 'omarchy-pkgs'" \
  sync_checkout "$BASE" "$TEMP_ROOT/missing.json"
jq '.pins[0].repository = "file:///tmp/omarchy"' "$PROPOSAL" > "$TEMP_ROOT/non-https.json"
expect_failure 'non-HTTPS proposal repository' 'unexpected repository' \
  sync_checkout "$BASE" "$TEMP_ROOT/non-https.json"

# A happy sync verifies, converges on repetition, and leaves no staging residue.
HAPPY="$TEMP_ROOT/happy"
cp -a "$BASE" "$HAPPY"
sync_checkout "$HAPPY" "$PROPOSAL" >/dev/null || fail 'happy sync failed'
"$HAPPY/scripts/upstream" verify >/dev/null || fail 'synchronized checkout does not verify'
first_fingerprint="$(fingerprint_active "$HAPPY")"
sync_checkout "$HAPPY" "$PROPOSAL" >/dev/null || fail 'convergent sync failed'
[[ "$(fingerprint_active "$HAPPY")" == "$first_fingerprint" ]] || fail 'second sync did not converge'
assert_no_staging "$HAPPY"

# Sync preserves tree modes, updates reference and payload together, excludes
# unselected Bash sources, and records exact provenance and transforms.
[[ -x "$HAPPY/packages/upstream/reference/omarchy/default/bash/bin/fixture-tool" ]] || fail 'executable tree mode was not preserved'
[[ ! -x "$HAPPY/packages/upstream/reference/omarchy/default/bash/env" ]] || fail 'regular tree mode changed'
for selected in shell aliases fns/tmux inputrc; do
  cmp -s "$HAPPY/packages/upstream/reference/omarchy/default/bash/$selected" \
    "$HAPPY/packages/upstream/bash/.config/dotfiles/upstream/bash/$selected" || \
    fail "sync did not update the selected Bash reference and payload together: $selected"
done
for excluded in env bin/fixture-tool; do
  [[ ! -e "$HAPPY/packages/upstream/bash/.config/dotfiles/upstream/bash/$excluded" ]] || \
    fail "sync materialized excluded Bash payload: $excluded"
done
jq -e --arg commit "$OMARCHY_COMMIT" '
  [
    .sources[] |
    select(.snapshot | startswith("packages/upstream/bash/")) |
    [.commit, .source.path, .destination.path]
  ] == [
    [$commit, "default/bash/shell", ".config/dotfiles/upstream/bash/shell"],
    [$commit, "default/bash/aliases", ".config/dotfiles/upstream/bash/aliases"],
    [$commit, "default/bash/fns/tmux", ".config/dotfiles/upstream/bash/fns/tmux"],
    [$commit, "default/bash/inputrc", ".config/dotfiles/upstream/bash/inputrc"]
  ]
' "$HAPPY/manifests/sources.json" >/dev/null || fail 'sync generated the wrong Bash payload provenance'
[[ "$(cat "$HAPPY/packages/upstream/nvim/.config/nvim/lua/config/keymaps.lua")" == *overlay* ]] || fail 'overlay did not replace starter content'
options="$HAPPY/packages/upstream/nvim/.config/nvim/lua/config/options.lua"
printf '%s' $'vim.opt.number = true\nrequire(\'config.remote_clipboard\').setup()\nvim.opt.relativenumber = false\nvim.g.autoformat = false\n' \
  > "$TEMP_ROOT/expected-options.lua"
cmp -s "$TEMP_ROOT/expected-options.lua" "$options" || fail 'append content or ordering is wrong'
jq -e --arg starter "$STARTER_COMMIT" --arg pkgs "$PKGS_COMMIT" '
  any(.sources[]; .source.path == "lua/config/options.lua" and .transform.type == "append") and
  any(.sources[]; .source.path == "pkgbuilds/omarchy-nvim/lua/config/keymaps.lua" and
    .commit == $pkgs and .transform.type == "overwrite" and
    .transform.replaces.commit == $starter and .transform.replaces.path == "lua/config/keymaps.lua")
' "$HAPPY/manifests/sources.json" >/dev/null || fail 'append/overwrite manifest records are wrong'
cmp -s "$LOCK_SOURCE" "$HAPPY/packages/upstream/nvim/.config/nvim/lazy-lock.json" || fail 'lazy-lock was not preserved'
git -C "$REPO_DIR" ls-files --error-unmatch packages/upstream/nvim/.config/nvim/lazy-lock.json >/dev/null || \
  fail 'relocated lazy-lock snapshot is not tracked'

# Unreachable commits, missing source paths, and symlinked sources are refused.
UNREACHABLE="$TEMP_ROOT/unreachable"
cp -a "$BASE" "$UNREACHABLE"
write_proposal "$TEMP_ROOT/unreachable.json" '0000000000000000000000000000000000000000'
expect_failure 'unreachable commit' 'unable to fetch commit' \
  sync_checkout "$UNREACHABLE" "$TEMP_ROOT/unreachable.json"

write_file "$OMARCHY_REPO/config/git/config" $'[fixture]\n\tsource = later\n'
rm -- "$OMARCHY_REPO/config/tmux/tmux.conf"
MISSING_COMMIT="$(commit_repo "$OMARCHY_REPO" 'missing required path')"
MISSING="$TEMP_ROOT/missing-path"
cp -a "$BASE" "$MISSING"
write_proposal "$TEMP_ROOT/missing-path.json" "$MISSING_COMMIT"
expect_failure 'missing source path' "missing source path in pin 'omarchy': config/tmux/tmux.conf" \
  sync_checkout "$MISSING" "$TEMP_ROOT/missing-path.json"

ln -s target "$OMARCHY_REPO/config/tmux/tmux.conf"
SYMLINK_COMMIT="$(commit_repo "$OMARCHY_REPO" 'symlink required path')"
SYMLINK="$TEMP_ROOT/symlink"
cp -a "$BASE" "$SYMLINK"
write_proposal "$TEMP_ROOT/symlink.json" "$SYMLINK_COMMIT"
expect_failure 'symlink source refusal' 'unsupported source mode 120000' \
  sync_checkout "$SYMLINK" "$TEMP_ROOT/symlink.json"

# Corruption of extracted staging content is detected and never reaches the
# active checkout.
CORRUPT="$TEMP_ROOT/extracted-corruption"
HOLD_DIR="$TEMP_ROOT/hold"
mkdir "$HOLD_DIR"
cp -a "$BASE" "$CORRUPT"
before="$(fingerprint_active "$CORRUPT")"
sync_checkout "$CORRUPT" "$PROPOSAL" DOTFILES_TEST_HOLD_AT=sync-extracted \
  DOTFILES_TEST_HOLD_DIR="$HOLD_DIR" > "$TEMP_ROOT/corruption.out" 2>&1 &
sync_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$HOLD_DIR/sync-extracted.ready" ]] && break
  sleep 0.02
done
[[ -e "$HOLD_DIR/sync-extracted.ready" ]] || fail 'sync did not reach the extracted-content hold'
staging_paths=("$CORRUPT"/.upstream-staging.*)
((${#staging_paths[@]} == 1)) && [[ -d "${staging_paths[0]}" ]] || fail 'held sync staging directory is unavailable'
printf 'corrupt\n' >> "${staging_paths[0]}/candidate/packages/upstream/git/.config/git/config"
: > "$HOLD_DIR/sync-extracted.release"
if wait "$sync_pid"; then
  fail 'extracted-content corruption unexpectedly succeeded'
fi
corruption_output="$(< "$TEMP_ROOT/corruption.out")"
[[ "$corruption_output" == *'extracted blob mismatch'* ]] || fail 'extracted-content corruption was not detected'
[[ "$(fingerprint_active "$CORRUPT")" == "$before" ]] || fail 'extracted-content corruption changed active content'
assert_no_staging "$CORRUPT"

# Injected faults at every sync phase leave active content untouched and clean.
for point in sync-proposal sync-fetch sync-enumerate sync-assemble sync-artifact sync-manifest \
  sync-candidate-verify sync-replace sync-replaced-tree; do
  fixture="$TEMP_ROOT/fault-$point"
  cp -a "$BASE" "$fixture"
  before="$(fingerprint_active "$fixture")"
  expect_failure "$point fault" "injected test failure at $point" \
    sync_checkout "$fixture" "$PROPOSAL" DOTFILES_TEST_FAIL_AT="$point"
  [[ "$(fingerprint_active "$fixture")" == "$before" ]] || fail "$point changed active content"
  assert_no_staging "$fixture"
done

# Bootstrap and library code can never invoke upstream sync.
if grep -Eq 'scripts/upstream[[:space:]]+sync|upstream[[:space:]]+sync' \
  "$REPO_DIR/bootstrap.sh" "$REPO_DIR"/lib/*.sh "$REPO_DIR"/lib/areas/*.sh; then
  fail 'bootstrap or library code can invoke upstream sync'
fi

printf 'PASS: offline upstream synchronization checks\n'
