#!/usr/bin/env bash

set -Eeuo pipefail

unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""

cleanup_test() { rm -rf -- "$TEST_ROOT"; }
trap cleanup_test EXIT
fail() { printf 'FAIL: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2; exit 1; }
pass() { ((TEST_COUNT += 1)); }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"; }

readonly LOADER_RELATIVE='.config/nvim/plugin/dotfiles-personal.lua'
readonly FAKE_NVIM="$TEST_ROOT/bin/nvim"
mkdir -p "$TEST_ROOT/bin"
printf '#!/usr/bin/env bash\nprintf "NVIM v0.12.4\\n"\n' > "$FAKE_NVIM"
chmod 0755 "$FAKE_NVIM"

# Skel-shaped native baseline mirroring the omarchy-nvim package layout.
make_native_home() {
  local home="$TEST_ROOT/home-$1"
  mkdir -p "$home/.config/nvim/lua/config" "$home/.config/nvim/lua/plugins" \
    "$home/.config/nvim/plugin/after" "$home/.local/state/dotfiles/v1"
  printf 'require("config.lazy")\n' > "$home/.config/nvim/init.lua"
  printf 'vim.opt.relativenumber = false\n' > "$home/.config/nvim/lua/config/options.lua"
  printf 'return {}\n' > "$home/.config/nvim/lua/plugins/theme.lua"
  printf '%s\n' '-- native transparency' > "$home/.config/nvim/plugin/after/transparency.lua"
  printf '%s' "$home"
}

run_nvim_area() {
  local home="$1" operation="$2" fail_at="${3:-}" mode=apply
  [[ "$operation" != remove ]] || mode=remove
  [[ "$operation" != check ]] || mode=check
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=stage9-nvim-test SELECTED_PROFILE=omarchy MODE="$mode" \
    DOTFILES_TESTING=1 DOTFILES_TEST_NVIM_BIN="$FAKE_NVIM" DOTFILES_TEST_FAIL_AT="$fail_at" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/nvim.sh"
      AREA_ORDER=(git bash tmux nvim zsh)
      AREA_STATUS=([git]=ready [bash]=ready [tmux]=ready [nvim]=ready [zsh]=ready)
      if [[ "$MODE" == remove ]]; then
        remove_nvim
      elif [[ "$MODE" == check ]]; then
        preflight_nvim
        check_nvim_restore_convergence
      else
        preflight_nvim
        apply_nvim
      fi
    '
}

loader_hash() { sha256sum "$1/$LOADER_RELATIVE" | cut -d' ' -f1; }

# A check on an undeployed native HOME reports the pending loader and mutates nothing.
home="$(make_native_home check)"
cp -a "$home" "$TEST_ROOT/check-before"
TEST_OUTPUT="$(run_nvim_area "$home" check 2>&1)" && fail 'undeployed native check unexpectedly converged'
assert_contains "$TEST_OUTPUT" 'pending native Neovim loader'
diff --no-dereference -r "$home" "$TEST_ROOT/check-before" >/dev/null || fail 'native check mutated HOME'
pass

# Apply creates the exact loader, links the personal layer, and records native state.
home="$(make_native_home lifecycle)"
cp -a "$home/.config/nvim" "$TEST_ROOT/native-before-apply"
run_nvim_area "$home" apply >/dev/null
[[ -f "$home/$LOADER_RELATIVE" && ! -L "$home/$LOADER_RELATIVE" ]] || fail 'loader was not created as a regular file'
[[ "$(stat -c %a -- "$home/$LOADER_RELATIVE")" == 644 ]] || fail 'loader mode is not 0644'
grep -qF -- '-- >>> dotfiles nvim >>>' "$home/$LOADER_RELATIVE" || fail 'loader lacks the begin marker'
grep -qF 'personal.lua' "$home/$LOADER_RELATIVE" || fail 'loader does not source the personal layer'
[[ -L "$home/.config/dotfiles/nvim/personal.lua" ]] || fail 'personal layer link was not deployed'
state="$home/.local/state/dotfiles/v1/nvim.json"
jq -e --arg hash "$(loader_hash "$home")" '
  .profile == "omarchy" and .packages == ["common/nvim"] and
  (.attachments | length == 1) and .attachments[0].id == "nvim-native-loader-v1.created" and
  .attachments[0].path == ".config/nvim/plugin/dotfiles-personal.lua" and
  (.restored_lock_sha256 == null) and .backups == [] and
  ([.managed_directories[] | select(startswith(".config/nvim"))] | length == 0)
' "$state" >/dev/null || fail 'native Neovim state is not the expected shape'
first_hash="$(loader_hash "$home")"
pass

# Reapply and check are idempotent and byte-stable.
run_nvim_area "$home" apply >/dev/null
[[ "$(loader_hash "$home")" == "$first_hash" ]] || fail 'reapply changed loader bytes'
run_nvim_area "$home" check >/dev/null || fail 'converged native check failed'
pass

# A simulated native refresh removes the loader; check fails with guidance and reapply reattaches.
rm -rf "$home/.config/nvim"
cp -a "$TEST_ROOT/native-before-apply" "$home/.config/nvim"
TEST_OUTPUT="$(run_nvim_area "$home" check 2>&1)" && fail 'post-refresh check unexpectedly converged'
assert_contains "$TEST_OUTPUT" 'pending native Neovim loader reattachment'
run_nvim_area "$home" apply >/dev/null
[[ "$(loader_hash "$home")" == "$first_hash" ]] || fail 'reattached loader bytes differ'
run_nvim_area "$home" check >/dev/null || fail 'post-reattachment check failed'
pass

# Loader drift refusals: modified interior, foreign bytes outside markers, and unrelated files.
printf '%s\n' '-- tampered' >> "$home/$LOADER_RELATIVE"
TEST_OUTPUT="$(run_nvim_area "$home" check 2>&1)" && fail 'drifted loader passed check'
assert_contains "$TEST_OUTPUT" 'native Neovim loader contains unmanaged content'
run_nvim_area "$home" apply >/dev/null 2>&1 && fail 'drifted loader was overwritten by apply'
# Interior tampering breaks the marker pair itself and refuses in the engine.
interior="$(make_native_home interior)"
run_nvim_area "$interior" apply >/dev/null
sed -i 's/^local personal = .*$/local personal = "tampered"/' "$interior/$LOADER_RELATIVE"
TEST_OUTPUT="$(run_nvim_area "$interior" check 2>&1)" && fail 'interior-tampered loader passed check'
assert_contains "$TEST_OUTPUT" 'guarded attachment is partial, malformed, nested, duplicate, or modified'
sed -i 's/-- tampered//' "$home/$LOADER_RELATIVE"
sed -i '${/^$/d}' "$home/$LOADER_RELATIVE"
run_nvim_area "$home" check >/dev/null || fail 'restored loader failed check'
pass

# A foreign file at the loader path refuses on a fresh HOME.
foreign="$(make_native_home foreign)"
printf '%s\n' '-- user file' > "$foreign/$LOADER_RELATIVE"
TEST_OUTPUT="$(run_nvim_area "$foreign" apply 2>&1)" && fail 'foreign loader path was adopted'
assert_contains "$TEST_OUTPUT" 'unrelated file exists at the native Neovim loader path'
pass

# A missing native baseline refuses before any mutation.
bare="$TEST_ROOT/home-bare"
mkdir -p "$bare/.local/state/dotfiles/v1"
TEST_OUTPUT="$(run_nvim_area "$bare" apply 2>&1)" && fail 'missing native baseline was accepted'
assert_contains "$TEST_OUTPUT" 'native Omarchy Neovim config is missing or unsafe'
pass

# Forged state refuses: wrong origin and wrong content hash.
for forgery in '.attachments[0].id = "nvim-native-loader-v1.existing-empty"' \
  '.attachments[0].content_hash = "0000000000000000000000000000000000000000000000000000000000000000"'; do
  forged="$(make_native_home "forged-$TEST_COUNT-${forgery//[^a-z]/}")" || true
  run_nvim_area "$forged" apply >/dev/null
  state="$forged/.local/state/dotfiles/v1/nvim.json"
  jq -c "$forgery" "$state" > "$state.new" && mv "$state.new" "$state" && chmod 0600 "$state"
  TEST_OUTPUT="$(run_nvim_area "$forged" check 2>&1)" && fail "forged state passed check: $forgery"
  assert_contains "$TEST_OUTPUT" 'unknown attachment'
done
pass

# Removal deletes the loader and links exactly; the native tree is byte-identical.
run_nvim_area "$home" remove >/dev/null
[[ ! -e "$home/$LOADER_RELATIVE" ]] || fail 'removal retained the loader'
[[ ! -e "$home/.local/state/dotfiles/v1/nvim.json" ]] || fail 'removal retained state'
[[ ! -e "$home/.config/dotfiles/nvim/personal.lua" ]] || fail 'removal retained the personal link'
diff --no-dereference -r "$home/.config/nvim" "$TEST_ROOT/native-before-apply" >/dev/null || \
  fail 'native tree differs from its pre-apply snapshot after removal'
pass

# Removal with an absent or drifted loader refuses and retains state.
run_nvim_area "$home" apply >/dev/null
rm "$home/$LOADER_RELATIVE"
TEST_OUTPUT="$(run_nvim_area "$home" remove 2>&1)" && fail 'removal proceeded with an absent loader'
assert_contains "$TEST_OUTPUT" 'recorded guarded attachment is absent'
[[ -f "$home/.local/state/dotfiles/v1/nvim.json" ]] || fail 'refused removal dropped state'
run_nvim_area "$home" apply >/dev/null 2>&1 || fail 'reattachment after refused removal failed'
run_nvim_area "$home" remove >/dev/null || fail 'clean removal failed after reattachment'
pass

# Fault injection at both attachment commit points rolls back to the pre-operation tree.
faulted="$(make_native_home faulted)"
cp -a "$faulted" "$TEST_ROOT/faulted-before"
TEST_OUTPUT="$(run_nvim_area "$faulted" apply nvim-after-attachment 2>&1)" && fail 'apply fault did not fail'
diff --no-dereference -r "$faulted" "$TEST_ROOT/faulted-before" >/dev/null || \
  fail 'apply fault did not roll back the HOME tree'
run_nvim_area "$faulted" apply >/dev/null
cp -a "$faulted" "$TEST_ROOT/faulted-applied"
TEST_OUTPUT="$(run_nvim_area "$faulted" remove nvim-remove-after-attachment 2>&1)" && fail 'remove fault did not fail'
diff --no-dereference -r "$faulted" "$TEST_ROOT/faulted-applied" >/dev/null || \
  fail 'remove fault did not roll back the HOME tree'
pass

printf 'PASS: %d Stage 9 native Neovim loader test groups\n' "$TEST_COUNT"
