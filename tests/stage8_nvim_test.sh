#!/usr/bin/env bash

set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RESTORE="$REPO_DIR/packages/generic/nvim/.local/share/dotfiles/bin/nvim-restore"

fail() {
  printf 'stage8_nvim_test: %s\n' "$1" >&2
  exit 1
}

[[ ! -e "$REPO_DIR/packages/generic/nvim/.empty-package" ]] || fail 'generic placeholder remains'
[[ ! -e "$REPO_DIR/packages/common/nvim/.empty-package" ]] || fail 'common placeholder remains'
[[ "$(stat -c %a -- "$RESTORE")" == 755 ]] || fail 'restore helper is not executable'
cmp -s "$REPO_DIR/packages/upstream/reference/omarchy/themes/tokyo-night/neovim.lua" \
  "$REPO_DIR/packages/generic/nvim/.config/nvim/lua/plugins/theme.lua" || fail 'Tokyo Night input drifted'
grep -F 'install = { missing = false' "$REPO_DIR/packages/upstream/nvim/.config/nvim/lua/config/lazy.lua" >/dev/null || fail 'missing-plugin installs are not disabled'
grep -F 'rocks = { enabled = false }' "$REPO_DIR/packages/upstream/nvim/.config/nvim/lua/config/lazy.lua" >/dev/null || fail 'Lua rocks are not disabled'
grep -F 'enabled = false, -- updates are checked only' "$REPO_DIR/packages/upstream/nvim/.config/nvim/lua/config/lazy.lua" >/dev/null || fail 'periodic checks are not disabled'
jq -e '. as $lock |
  all(["LazyVim", "lazy.nvim", "tokyonight.nvim", "mason.nvim", "mason-lspconfig.nvim",
    "nvim-lspconfig", "nvim-treesitter"][]; $lock[.] != null)
' "$REPO_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json" >/dev/null || fail 'generic shared specs lack lock coverage'
grep -F 'opts.ensure_installed = {}' "$REPO_DIR/packages/generic/nvim/.config/nvim/lua/plugins/dotfiles-runtime-policy.lua" >/dev/null || fail 'runtime installers are not explicitly empty'
grep -F 'prebuilt_binaries = { download = false }' "$REPO_DIR/packages/generic/nvim/.config/nvim/lua/plugins/dotfiles-runtime-policy.lua" >/dev/null || fail 'Blink binary downloading is not disabled'
[[ "$(git -C "$REPO_DIR" hash-object packages/upstream/nvim/.config/nvim/init.lua)" == \
  "$(jq -r '.sources[] | select(.source.path == "init.lua").transform.output_blob' "$REPO_DIR/manifests/sources.json")" ]] || fail 'init transform provenance drifted'
[[ "$(git -C "$REPO_DIR" hash-object packages/upstream/nvim/.config/nvim/lua/config/lazy.lua)" == \
  "$(jq -r '.sources[] | select(.source.path == "lua/config/lazy.lua").transform.output_blob' "$REPO_DIR/manifests/sources.json")" ]] || fail 'lazy transform provenance drifted'

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
home="$fixture/home"
repos="$fixture/repos"
mkdir -p "$home/.config/nvim" "$home/.local/share/dotfiles/bin" "$repos"
cp "$RESTORE" "$home/.local/share/dotfiles/bin/nvim-restore"
cp "$REPO_DIR/packages/generic/nvim/.local/share/dotfiles/bin/nvim-record-restore" \
  "$home/.local/share/dotfiles/bin/nvim-record-restore"

make_repo() {
  local name="$1"
  mkdir -p "$repos/$name"
  git -C "$repos/$name" init -q
  git -C "$repos/$name" -c user.name=test -c user.email=test@example.invalid \
    commit --allow-empty -qm initial
  git -C "$repos/$name" rev-parse HEAD
}

lazy_commit="$(make_repo lazy.nvim)"
sample_commit="$(make_repo sample.nvim)"
jq -cn --arg lazy "$lazy_commit" --arg sample "$sample_commit" \
  '{"lazy.nvim":{branch:"main",commit:$lazy},"sample.nvim":{branch:"main",commit:$sample}}' \
  > "$fixture/deployed-lock.json"
ln -s "$fixture/deployed-lock.json" "$home/.config/nvim/lazy-lock.json"
lock_before="$(sha256sum "$fixture/deployed-lock.json" | cut -d' ' -f1)"
mkdir -p "$home/.local/state/dotfiles/v1"
jq -cn --arg home "$home" --arg source "$(readlink -- "$home/.config/nvim/lazy-lock.json")" \
  --arg resolved "$fixture/deployed-lock.json" \
  '{schema_version:1,profile:"generic",area:"nvim",checkout_root:"/fixture",target_root:$home,
    packages:["upstream/nvim","generic/nvim","common/nvim"],
    targets:[{path:".config/nvim/lazy-lock.json",source:$source,resolved_source:$resolved}],
    managed_directories:[],attachments:[],backups:[]}' > "$home/.local/state/dotfiles/v1/nvim.json"
chmod 0600 "$home/.local/state/dotfiles/v1/nvim.json"

cat > "$fixture/nvim" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
lock="$HOME/.config/nvim/lazy-lock.json"
root="$HOME/.local/share/nvim/lazy"
while IFS=$'\t' read -r name commit; do
  if [[ ! -e "$root/$name" ]]; then
    git clone -q "$FIXTURE_REPOS/$name" "$root/$name"
  fi
  git -C "$root/$name" checkout -q "$commit"
done < <(jq -r 'to_entries[] | [.key,.value.commit] | @tsv' "$lock")
if [[ -n "${FIXTURE_INVOKED_LOG:-}" ]]; then printf '%s\n' "$$" >> "$FIXTURE_INVOKED_LOG"; fi
if [[ -n "${FIXTURE_HOLD_DIR:-}" ]]; then
  : > "$FIXTURE_HOLD_DIR/ready"
  while [[ ! -e "$FIXTURE_HOLD_DIR/release" ]]; do sleep 0.02; done
fi
if [[ "${FIXTURE_SIGNAL_PARENT:-0}" == 1 ]]; then kill -TERM "$PPID"; fi
EOF
chmod 0755 "$fixture/nvim"

HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" \
  "$home/.local/share/dotfiles/bin/nvim-restore" --first-launch >/dev/null
[[ "$(sha256sum "$home/.config/nvim/lazy-lock.json" | cut -d' ' -f1)" == "$lock_before" ]] || fail 'restore mutated the lockfile'
[[ "$(jq -r .restored_lock_sha256 "$home/.local/state/dotfiles/v1/nvim.json")" == "$lock_before" ]] || fail 'restore marker was not recorded in nvim.json'
[[ ! -e "$home/.local/state/dotfiles/nvim-restored-lock" ]] || fail 'restore created a transitional sidecar marker'
[[ "$(git -C "$home/.local/share/nvim/lazy/lazy.nvim" rev-parse HEAD)" == "$lazy_commit" ]] || fail 'lazy.nvim was not locked'
[[ "$(git -C "$home/.local/share/nvim/lazy/sample.nvim" rev-parse HEAD)" == "$sample_commit" ]] || fail 'plugin was not locked'

git -C "$repos/sample.nvim" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty -qm next
next_commit="$(git -C "$repos/sample.nvim" rev-parse HEAD)"
jq --arg commit "$next_commit" '."sample.nvim".commit = $commit' \
  "$fixture/deployed-lock.json" > "$fixture/next-lock"
mv "$fixture/next-lock" "$fixture/deployed-lock.json"
HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" \
  "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null
[[ "$(git -C "$home/.local/share/nvim/lazy/sample.nvim" rev-parse HEAD)" == "$next_commit" ]] || fail 'explicit restore did not converge'
compgen -G "$home/.local/state/dotfiles/nvim-preserved/*/sample.nvim" >/dev/null || fail 'divergent checkout was not preserved'

touch "$home/.local/share/nvim/lazy/sample.nvim/dirty"
if HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" \
  "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null 2>&1; then
  fail 'dirty checkout was accepted'
fi
[[ -e "$home/.local/share/nvim/lazy/sample.nvim/dirty" ]] || fail 'dirty checkout was not preserved'
rm "$home/.local/share/nvim/lazy/sample.nvim/dirty"

# Lock keys are safe single path components. In particular, dot components can
# never turn rollback cleanup into removal of the plugin root or its parent.
cp "$fixture/deployed-lock.json" "$fixture/valid-lock"
for adversarial_name in . ..; do
  jq --arg name "$adversarial_name" --arg commit "$sample_commit" \
    '. + {($name):{branch:"main",commit:$commit}}' "$fixture/valid-lock" > "$fixture/deployed-lock.json"
  if HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
    DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null 2>&1; then
    fail "restore accepted adversarial plugin name $adversarial_name"
  fi
  [[ -d "$home/.local/share/nvim/lazy/sample.nvim/.git" ]] || fail 'adversarial lock damaged the plugin root'
done
cp "$fixture/valid-lock" "$fixture/deployed-lock.json"

# The callback runs only after checkout convergence, and callback failure rolls
# all replacements back without advancing state or losing the old checkout.
git -C "$repos/sample.nvim" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty -qm third
third_commit="$(git -C "$repos/sample.nvim" rev-parse HEAD)"
jq --arg commit "$third_commit" '."sample.nvim".commit = $commit' \
  "$fixture/deployed-lock.json" > "$fixture/third-lock"
mv "$fixture/third-lock" "$fixture/deployed-lock.json"
cat > "$fixture/failing-callback" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$(git -C "$HOME/.local/share/nvim/lazy/sample.nvim" rev-parse HEAD)" == "$EXPECTED_PLUGIN_COMMIT" ]]
: > "$CALLBACK_SEEN"
exit 1
EOF
chmod 0755 "$fixture/failing-callback"
state="$home/.local/state/dotfiles/v1/nvim.json"
marker_before="$(jq -r .restored_lock_sha256 "$state")"
if HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
  DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" DOTFILES_NVIM_RESTORE_CALLBACK="$fixture/failing-callback" \
  EXPECTED_PLUGIN_COMMIT="$third_commit" CALLBACK_SEEN="$fixture/callback-seen" \
  "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null 2>&1; then
  fail 'restore accepted a failing completion callback'
fi
[[ -e "$fixture/callback-seen" ]] || fail 'restore callback ran before plugin convergence'
[[ "$(git -C "$home/.local/share/nvim/lazy/sample.nvim" rev-parse HEAD)" == "$next_commit" ]] || \
  fail 'callback failure did not restore the replaced checkout'
[[ "$(jq -r .restored_lock_sha256 "$state")" == "$marker_before" ]] || fail 'callback failure advanced restore state'
HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
  DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null
[[ "$(git -C "$home/.local/share/nvim/lazy/sample.nvim" rev-parse HEAD)" == "$third_commit" ]] || \
  fail 'explicit rerun did not converge after callback rollback'

# TERM during the restore command rolls replaced checkouts back and never runs
# the completion callback. A later explicit restore remains possible.
git -C "$repos/sample.nvim" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty -qm fourth
fourth_commit="$(git -C "$repos/sample.nvim" rev-parse HEAD)"
jq --arg commit "$fourth_commit" '."sample.nvim".commit = $commit' \
  "$fixture/deployed-lock.json" > "$fixture/fourth-lock"
mv "$fixture/fourth-lock" "$fixture/deployed-lock.json"
marker_before="$(jq -r .restored_lock_sha256 "$state")"
set +e
HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
  DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" FIXTURE_SIGNAL_PARENT=1 \
  "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null 2>&1
signal_status=$?
set -e
[[ "$signal_status" == 143 ]] || fail 'restore termination did not preserve status 143'
[[ "$(git -C "$home/.local/share/nvim/lazy/sample.nvim" rev-parse HEAD)" == "$third_commit" ]] || \
  fail 'terminated restore did not roll back the replaced checkout'
[[ "$(jq -r .restored_lock_sha256 "$state")" == "$marker_before" ]] || fail 'terminated restore advanced callback state'
HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
  DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null

# The state-root flock serializes the complete restore, including callback.
hold="$fixture/restore-hold"; mkdir "$hold"; : > "$fixture/invoked.log"
HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
  DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" FIXTURE_HOLD_DIR="$hold" FIXTURE_INVOKED_LOG="$fixture/invoked.log" \
  "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null &
first_restore_pid=$!
for _ in {1..500}; do [[ -e "$hold/ready" ]] && break; sleep 0.02; done
[[ -e "$hold/ready" ]] || fail 'first concurrent restore did not reach its hold'
HOME="$home" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" \
  DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" FIXTURE_INVOKED_LOG="$fixture/invoked.log" \
  "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null &
second_restore_pid=$!
sleep 0.1
[[ "$(wc -l < "$fixture/invoked.log")" == 1 ]] || fail 'concurrent restore bypassed the restore lock'
kill -0 "$second_restore_pid" 2>/dev/null || fail 'second restore did not wait for the first restore lock'
: > "$hold/release"
wait "$first_restore_pid" || fail 'first concurrent restore failed'
wait "$second_restore_pid" || fail 'second concurrent restore failed'
[[ "$(wc -l < "$fixture/invoked.log")" == 2 ]] || fail 'serialized second restore did not execute'

# Symlink-escaping and relative XDG roots refuse before invoking Neovim.
mkdir "$fixture/outside-data"
ln -s "$fixture/outside-data" "$home/escaped-data"
for bad_data in relative-data "$home/escaped-data"; do
  if HOME="$home" XDG_DATA_HOME="$bad_data" FIXTURE_REPOS="$repos" DOTFILES_TESTING=1 \
    DOTFILES_NVIM_LAZY_REPOSITORY="$repos/lazy.nvim" DOTFILES_NVIM_EXECUTABLE="$fixture/nvim" \
    "$home/.local/share/dotfiles/bin/nvim-restore" >/dev/null 2>&1; then
    fail "restore accepted unsafe XDG data root $bad_data"
  fi
done
[[ -z "$(find "$fixture/outside-data" -mindepth 1 -print -quit)" ]] || fail 'XDG escape refusal mutated the outside root'

# The callback is an atomic state CAS and rejects stale hashes and malformed state.
state="$home/.local/state/dotfiles/v1/nvim.json"
state_before="$(sha256sum "$state")"
if HOME="$home" "$home/.local/share/dotfiles/bin/nvim-record-restore" "$lock_before" >/dev/null 2>&1; then
  fail 'restore callback accepted a stale lock hash'
fi
[[ "$(sha256sum "$state")" == "$state_before" ]] || fail 'stale callback changed state'
cp "$state" "$fixture/valid-state"
printf '{}\n' > "$state"; chmod 0600 "$state"
if HOME="$home" "$home/.local/share/dotfiles/bin/nvim-record-restore" "$(sha256sum "$fixture/deployed-lock.json" | cut -d' ' -f1)" >/dev/null 2>&1; then
  fail 'restore callback accepted malformed state'
fi
mv "$fixture/valid-state" "$state"; chmod 0600 "$state"

run_nvim_area() {
  local lifecycle_home="$1" profile="$2" operation="$3" fail_at="${4:-}" mode=apply
  [[ "$operation" != check ]] || mode=check
  [[ "$operation" != remove ]] || mode=remove
  HOME="$lifecycle_home" TARGET_ROOT="$lifecycle_home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=stage8-nvim-test SELECTED_PROFILE="$profile" MODE="$mode" DOTFILES_TESTING=1 \
    DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" DOTFILES_TEST_TIMESTAMP=20260720T120000Z \
    DOTFILES_TEST_FAIL_AT="$fail_at" STAGE8_FAST="${STAGE8_FAST:-0}" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/nvim.sh"
      if [[ "$STAGE8_FAST" == 1 ]]; then validate_nvim_payload() { :; }; fi
      AREA_ORDER=(git bash tmux nvim zsh)
      AREA_STATUS=([git]=ready [bash]=ready [tmux]=ready [nvim]=framework [zsh]=ready)
      if [[ "$MODE" == remove ]]; then remove_nvim
      elif [[ "$MODE" == check ]]; then preflight_nvim
      else preflight_nvim; apply_nvim
      fi
    '
}

cat > "$fixture/nvim-version" <<'EOF'
#!/usr/bin/env bash
printf 'NVIM v0.12.4\n'
EOF
chmod 0755 "$fixture/nvim-version"

# Default roots move once, collision names do not clobber, reapply is stable,
# and removal retains backups and the migration ledger.
lifecycle="$fixture/lifecycle-default"
mkdir -p "$lifecycle/.local/share/nvim" "$lifecycle/.local/state/nvim" "$lifecycle/.cache/nvim"
mkdir -p "$lifecycle/.local/state/dotfiles"
printf data > "$lifecycle/.local/share/nvim/data"
printf state > "$lifecycle/.local/state/nvim/state"
printf cache > "$lifecycle/.cache/nvim/cache"
printf '%064d\n' 0 > "$lifecycle/.local/state/dotfiles/nvim-restored-lock"
chmod 0600 "$lifecycle/.local/state/dotfiles/nvim-restored-lock"
mkdir "$lifecycle/.cache/nvim.20260720T120000Z.bak"
run_nvim_area "$lifecycle" generic check >/dev/null
[[ -d "$lifecycle/.local/share/nvim" ]] || fail 'check mutated default runtime roots'
run_nvim_area "$lifecycle" generic apply >/dev/null
nvim_state="$lifecycle/.local/state/dotfiles/v1/nvim.json"
ledger="$lifecycle/.local/state/dotfiles/v1/migrations.json"
[[ -f "$nvim_state" && ! -e "$lifecycle/.local/share/nvim" && -f "$lifecycle/.local/share/nvim.20260720T120000Z.bak/data" ]] || fail 'default runtime migration failed'
[[ ! -e "$lifecycle/.local/state/dotfiles/nvim-restored-lock" && "$(jq -r '.restored_lock_sha256 // empty' "$nvim_state")" == '' ]] || fail 'transitional marker was imported or retained'
[[ -f "$lifecycle/.cache/nvim.20260720T120000Z.1.bak/cache" ]] || fail 'collision-free runtime backup naming failed'
jq -e '([.migrations[].id] | sort) == (["nvim-runtime-v1-cache","nvim-runtime-v1-data","nvim-runtime-v1-state"] | sort)' "$ledger" >/dev/null || fail 'runtime completion ledger is incomplete'
ledger_before="$(sha256sum "$ledger")"
deployed_hash="$(sha256sum "$lifecycle/.config/nvim/lazy-lock.json" | cut -d' ' -f1)"
jq --arg hash "$deployed_hash" '.restored_lock_sha256=$hash' "$nvim_state" > "$nvim_state.tmp"
mv "$nvim_state.tmp" "$nvim_state"; chmod 0600 "$nvim_state"
run_nvim_area "$lifecycle" generic apply >/dev/null
[[ "$(sha256sum "$ledger")" == "$ledger_before" ]] || fail 'reapply changed completed runtime migrations'
[[ "$(jq -r .restored_lock_sha256 "$nvim_state")" == "$deployed_hash" ]] || fail 'reapply did not preserve a marker matching the deployed lock'
jq '.restored_lock_sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$nvim_state" > "$nvim_state.tmp"
mv "$nvim_state.tmp" "$nvim_state"; chmod 0600 "$nvim_state"
run_nvim_area "$lifecycle" generic apply >/dev/null
[[ "$(jq -r '.restored_lock_sha256 // empty' "$nvim_state")" == '' ]] || fail 'reapply preserved a stale restore marker'

# Existing state without the complete runtime ledger is never allowed to
# reinterpret newly generated runtime data as pre-deployment data.
cp "$ledger" "$fixture/saved-ledger"
rm "$ledger"
mkdir -p "$lifecycle/.local/share/nvim/generated"
if STAGE8_FAST=1 run_nvim_area "$lifecycle" generic apply >/dev/null 2>&1; then
  fail 'existing Neovim state without its runtime ledger was accepted'
fi
[[ -d "$lifecycle/.local/share/nvim/generated" ]] || fail 'missing-ledger refusal remigrated generated runtime data'
mv "$fixture/saved-ledger" "$ledger"; chmod 0600 "$ledger"
mkdir -p "$lifecycle/.local/share/nvim/lazy/retained" "$lifecycle/.local/state/dotfiles/nvim-preserved/retained"
run_nvim_area "$lifecycle" generic remove >/dev/null
[[ ! -e "$nvim_state" && -f "$ledger" && -d "$lifecycle/.local/share/nvim/lazy/retained" && -d "$lifecycle/.local/state/dotfiles/nvim-preserved/retained" ]] || fail 'remove did not retain Neovim runtime and ledger data'
STAGE8_FAST=1 run_nvim_area "$lifecycle" generic apply >/dev/null
[[ -d "$lifecycle/.local/share/nvim/generated" && ! -e "$lifecycle/.local/share/nvim.20260720T120000Z.1.bak" ]] || \
  fail 'reapply after removal remigrated retained/generated runtime data'
STAGE8_FAST=1 run_nvim_area "$lifecycle" generic remove >/dev/null

# Custom HOME-contained XDG roots are supported; external roots refuse before mutation.
custom="$fixture/lifecycle-custom"
mkdir -p "$custom/xdg/data/nvim" "$custom/xdg/state/nvim" "$custom/xdg/cache/nvim"
printf x > "$custom/xdg/data/nvim/value"
HOME="$custom" XDG_DATA_HOME="$custom/xdg/data" XDG_STATE_HOME="$custom/xdg/state" XDG_CACHE_HOME="$custom/xdg/cache" \
  TARGET_ROOT="$custom" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage8-nvim-test \
  SELECTED_PROFILE=wsl MODE=apply DOTFILES_TESTING=1 DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" \
  DOTFILES_TEST_TIMESTAMP=20260720T120000Z bash -c '
    set -Eeuo pipefail; source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"; source "$DOTFILES_DIR/lib/areas/nvim.sh"
    AREA_ORDER=(git bash tmux nvim zsh); AREA_STATUS=([git]=ready [bash]=ready [tmux]=ready [nvim]=framework [zsh]=ready)
    preflight_nvim; apply_nvim
  ' >/dev/null
[[ -f "$custom/xdg/data/nvim.20260720T120000Z.bak/value" ]] || fail 'custom XDG runtime root was not preserved'
external="$fixture/external"; mkdir -p "$external/nvim" "$fixture/external-home"
if HOME="$fixture/external-home" XDG_DATA_HOME="$external" run_nvim_area "$fixture/external-home" generic check >/dev/null 2>&1; then
  fail 'external XDG root was accepted'
fi
[[ -d "$external/nvim" && ! -e "$fixture/external-home/.config" ]] || fail 'external-root refusal mutated paths'
mkdir -p "$fixture/symlink-home/xdg" "$fixture/symlink-outside/nvim"
ln -s "$fixture/symlink-outside" "$fixture/symlink-home/xdg/data"
if HOME="$fixture/symlink-home" XDG_DATA_HOME="$fixture/symlink-home/xdg/data" \
  run_nvim_area "$fixture/symlink-home" generic check >/dev/null 2>&1; then
  fail 'symlink-escaping lifecycle XDG root was accepted'
fi

# A failure after all moves restores directories and leaves no state or ledger.
rollback_home="$fixture/lifecycle-rollback"
mkdir -p "$rollback_home/.local/share/nvim" "$rollback_home/.local/state/nvim" "$rollback_home/.cache/nvim"
printf keep > "$rollback_home/.local/share/nvim/value"
if run_nvim_area "$rollback_home" generic apply nvim-after-state >/dev/null 2>&1; then fail 'faulted lifecycle apply succeeded'; fi
[[ -f "$rollback_home/.local/share/nvim/value" && -d "$rollback_home/.local/state/nvim" && -d "$rollback_home/.cache/nvim" && ! -e "$rollback_home/.local/state/dotfiles/v1/nvim.json" ]] || fail 'directory-move rollback was incomplete'

# Every boundary after migration starts must restore all three roots and both
# state files, including failures after state and ledger writes.
for boundary in nvim-after-data-move nvim-after-state-move nvim-after-cache-move \
  nvim-after-stow nvim-after-state nvim-after-ledger; do
  crash_home="$fixture/crash-$boundary"
  mkdir -p "$crash_home/.local/share/nvim" "$crash_home/.local/state/nvim" "$crash_home/.cache/nvim"
  printf data > "$crash_home/.local/share/nvim/value"
  printf state > "$crash_home/.local/state/nvim/value"
  printf cache > "$crash_home/.cache/nvim/value"
  if STAGE8_FAST=1 run_nvim_area "$crash_home" generic apply "$boundary" >/dev/null 2>&1; then
    fail "fault boundary $boundary succeeded"
  fi
  [[ "$(< "$crash_home/.local/share/nvim/value")" == data && \
    "$(< "$crash_home/.local/state/nvim/value")" == state && \
    "$(< "$crash_home/.cache/nvim/value")" == cache ]] || fail "$boundary did not restore every runtime root"
  [[ ! -e "$crash_home/.local/state/dotfiles/v1/nvim.json" && \
    ! -e "$crash_home/.local/state/dotfiles/v1/migrations.json" ]] || fail "$boundary retained state or ledger writes"
done

# Reviewed individual and folded links use lexical ownership, including broken
# links, while unrelated files refuse. The preserved old checkout is untouched.
legacy_repo="$fixture/legacy-repo"
old_checkout="$fixture/old-checkout"
mkdir -p "$legacy_repo" "$old_checkout/.config/nvim"
cp -a "$REPO_DIR/packages" "$REPO_DIR/profiles" "$REPO_DIR/manifests" "$legacy_repo/"
mkdir -p "$legacy_repo/lib/stow-preflight-target"
run_legacy_area() {
  local legacy_home="$1" operation="$2" fail_at="${3:-}"
  jq --arg home "$legacy_home" --arg root "$old_checkout" \
    '(.hosts[] | select(.id == "wsl-ubuntu") | .home)=$home |
     (.hosts[] | select(.id == "wsl-ubuntu") | .checkout_root)=$root' \
    "$REPO_DIR/manifests/legacy-links.json" > "$legacy_repo/manifests/legacy-links.json"
  HOME="$legacy_home" TARGET_ROOT="$legacy_home" CHECKOUT_ROOT="$legacy_repo" DOTFILES_DIR="$legacy_repo" \
    SCRIPT_NAME=stage8-nvim-legacy SELECTED_PROFILE=generic MODE=apply DOTFILES_TESTING=1 \
    DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" DOTFILES_TEST_TIMESTAMP=20260720T120000Z \
    DOTFILES_TEST_FAIL_AT="$fail_at" ENGINE_DIR="$REPO_DIR" bash -c '
      set -Eeuo pipefail; source "$ENGINE_DIR/lib/common.sh"; source "$ENGINE_DIR/lib/engine.sh"
      source "$ENGINE_DIR/lib/provisioning.sh"; source "$ENGINE_DIR/lib/areas/nvim.sh"
      validate_nvim_payload() { :; }
      AREA_ORDER=(git bash tmux nvim zsh); AREA_STATUS=([git]=ready [bash]=ready [tmux]=ready [nvim]=framework [zsh]=ready)
      preflight_nvim; [[ "$1" == check ]] || apply_nvim
    ' _ "$operation"
}
legacy_home="$fixture/legacy-individual"; mkdir -p "$legacy_home/.config/nvim"
ln -s "$old_checkout/.config/nvim/init.lua" "$legacy_home/.config/nvim/init.lua"
run_legacy_area "$legacy_home" apply >/dev/null
[[ -L "$legacy_home/.config/nvim/init.lua" && "$(realpath -m "$legacy_home/.config/nvim/init.lua")" == "$legacy_repo/packages/upstream/nvim/.config/nvim/init.lua" ]] || fail 'broken reviewed individual link was not replaced'
[[ -d "$old_checkout/.config/nvim" ]] || fail 'tracked legacy source tree was changed'
folded_home="$fixture/legacy-folded"; mkdir -p "$folded_home/.config"
ln -s "$old_checkout/.config/nvim" "$folded_home/.config/nvim"
if run_legacy_area "$folded_home" apply nvim-after-stow >/dev/null 2>&1; then fail 'folded rollback fault succeeded'; fi
[[ -L "$folded_home/.config/nvim" && "$(readlink "$folded_home/.config/nvim")" == "$old_checkout/.config/nvim" && ! -e "$folded_home/.local/state/dotfiles/v1/nvim.json" ]] || fail 'folded legacy rollback did not restore the exact link'
run_legacy_area "$folded_home" apply >/dev/null
[[ -d "$folded_home/.config/nvim" && ! -L "$folded_home/.config/nvim" ]] || fail 'folded reviewed topology was not migrated'
conflict_home="$fixture/legacy-conflict"; mkdir -p "$conflict_home/.config/nvim"; printf unrelated > "$conflict_home/.config/nvim/init.lua"
if run_legacy_area "$conflict_home" check >/dev/null 2>&1; then fail 'unrelated Neovim conflict was accepted'; fi
[[ "$(<"$conflict_home/.config/nvim/init.lua")" == unrelated ]] || fail 'conflict refusal mutated unrelated data'

# Exercise the same dispatch through bootstrap with an isolated checkout whose
# test-only area row is ready. The repository row remains framework below.
bootstrap_repo="$fixture/bootstrap-repo"
cp -a "$REPO_DIR" "$bootstrap_repo"
perl -0pi -e 's/area\|nvim\|framework/area|nvim|ready/' "$bootstrap_repo/manifests/areas.tsv"
bootstrap_home="$fixture/bootstrap-home"; host_root="$fixture/host-root"
mkdir -p "$bootstrap_home" "$host_root/etc" "$host_root/proc/sys/kernel"
printf 'ID=ubuntu\nVERSION_ID=24.04\n' > "$host_root/etc/os-release"
printf '6.8.0-generic\n' > "$host_root/proc/sys/kernel/osrelease"
PATH="$(dirname "$fixture/nvim-version"):$PATH" HOME="$bootstrap_home" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$host_root" DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" \
  "$bootstrap_repo/bootstrap.sh" --profile generic --area nvim >/dev/null
set +e
pending_output="$(HOME="$bootstrap_home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host_root" \
  DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" "$bootstrap_repo/bootstrap.sh" \
  --check --profile generic --area nvim 2>&1)"
pending_status=$?
set -e
if ((pending_status == 0)); then
  fail 'bootstrap check claimed convergence before the first restore'
fi
[[ "$pending_output" == *'pending Neovim restore: restored_lock_sha256 is absent'* ]] || \
  fail 'bootstrap check did not clearly report a pending first restore'
bootstrap_state="$bootstrap_home/.local/state/dotfiles/v1/nvim.json"
bootstrap_lock_hash="$(sha256sum "$bootstrap_home/.config/nvim/lazy-lock.json" | cut -d' ' -f1)"
jq '.restored_lock_sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$bootstrap_state" > "$bootstrap_state.tmp"
mv "$bootstrap_state.tmp" "$bootstrap_state"; chmod 0600 "$bootstrap_state"
set +e
stale_output="$(HOME="$bootstrap_home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host_root" \
  DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" "$bootstrap_repo/bootstrap.sh" \
  --check --profile generic --area nvim 2>&1)"
stale_status=$?
set -e
[[ "$stale_status" != 0 && "$stale_output" == *'stale Neovim restore:'* ]] || \
  fail 'bootstrap check did not clearly report a stale restore'
jq --arg hash "$bootstrap_lock_hash" '.restored_lock_sha256=$hash' "$bootstrap_state" > "$bootstrap_state.tmp"
mv "$bootstrap_state.tmp" "$bootstrap_state"; chmod 0600 "$bootstrap_state"
HOME="$bootstrap_home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host_root" DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" \
  "$bootstrap_repo/bootstrap.sh" --check --profile generic --area nvim >/dev/null
HOME="$bootstrap_home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host_root" DOTFILES_TEST_NVIM_BIN="$fixture/nvim-version" \
  "$bootstrap_repo/bootstrap.sh" --profile generic --area nvim >/dev/null
HOME="$bootstrap_home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host_root" \
  "$bootstrap_repo/bootstrap.sh" --remove --area nvim >/dev/null
[[ ! -e "$bootstrap_home/.local/state/dotfiles/v1/nvim.json" && -f "$bootstrap_home/.local/state/dotfiles/v1/migrations.json" ]] || fail 'bootstrap lifecycle dispatch did not remove state and retain ledger'

# Framework readiness remains a hard live-rollout gate.
mkdir "$fixture/framework-home"
if HOME="$fixture/framework-home" "$REPO_DIR/bootstrap.sh" --profile generic --area nvim >/dev/null 2>&1; then
  fail 'repository framework manifest allowed Neovim rollout'
fi

printf 'stage8_nvim_test: PASS\n'
