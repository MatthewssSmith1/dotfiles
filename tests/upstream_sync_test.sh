#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly LOCK_SOURCE="$REPO_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json"
readonly LOCK_SHA256='0bf36c5e91f71bc3659391761b3856ab7dfcaeda8aca6a3de954d9a06e7e28de'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local description="$1" expected="$2" output
  shift 2
  if output="$("$@" 2>&1)"; then
    fail "$description unexpectedly succeeded"
  fi
  [[ "$output" == *"$expected"* ]] || {
    printf '%s\n' "$output" >&2
    fail "$description did not report '$expected'"
  }
}

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

bash -n "$REPO_DIR/scripts/upstream" || fail 'scripts/upstream has invalid Bash syntax'
command -v jq >/dev/null || fail 'jq is required'
command -v git >/dev/null || fail 'git is required'
[[ "$(sha256sum "$LOCK_SOURCE" | cut -d' ' -f1)" == "$LOCK_SHA256" ]] || fail 'fixture lazy-lock does not match the accepted constant'

readonly TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_ROOT"' EXIT
make_repositories "$TEMP_ROOT"
BASE="$TEMP_ROOT/base"
seed_active_checkout "$BASE"
PROPOSAL="$TEMP_ROOT/proposal.json"
write_proposal "$PROPOSAL"

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

HAPPY="$TEMP_ROOT/happy"
cp -a "$BASE" "$HAPPY"
sync_checkout "$HAPPY" "$PROPOSAL" >/dev/null || fail 'happy sync failed'
"$HAPPY/scripts/upstream" verify >/dev/null || fail 'synchronized checkout does not verify'
first_fingerprint="$(fingerprint_active "$HAPPY")"
sync_checkout "$HAPPY" "$PROPOSAL" >/dev/null || fail 'convergent sync failed'
[[ "$(fingerprint_active "$HAPPY")" == "$first_fingerprint" ]] || fail 'second sync did not converge'
assert_no_staging "$HAPPY"

[[ -x "$HAPPY/packages/upstream/reference/omarchy/default/bash/bin/fixture-tool" ]] || fail 'executable tree mode was not preserved'
[[ ! -x "$HAPPY/packages/upstream/reference/omarchy/default/bash/env" ]] || fail 'regular tree mode changed'
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

if grep -Eq 'scripts/upstream[[:space:]]+sync|upstream[[:space:]]+sync' \
  "$REPO_DIR/bootstrap.sh" "$REPO_DIR"/lib/*.sh "$REPO_DIR"/lib/areas/*.sh; then
  fail 'bootstrap or library code can invoke upstream sync'
fi

printf 'PASS: offline upstream synchronization checks\n'
