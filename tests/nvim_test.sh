#!/usr/bin/env bash
# Focused Neovim lean closure, native loader, restore, and offline startup tests.

set -Eeuo pipefail

unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

test_bin="$TEST_ROOT/bin"
install_fake_stow "$test_bin"
export PATH="$test_bin:$PATH"

readonly RESTORE="$REPO_DIR/packages/ubuntu/nvim/.local/share/dotfiles/bin/nvim-restore"
readonly LOCKFILE="$REPO_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json"
readonly LAZY_COMMIT="$(jq -r '."lazy.nvim".commit' "$LOCKFILE")"

[[ "$(awk '$1 == "nvim" {print $2}' "$REPO_DIR/profiles/ubuntu.conf")" == \
  upstream/nvim,ubuntu/nvim,common/nvim ]] || fail 'Ubuntu Neovim closure is not final'
[[ "$(awk '$1 == "nvim" {print $2}' "$REPO_DIR/profiles/omarchy.conf")" == common/nvim ]] ||
  fail 'native Neovim closure is not personal-only'
[[ -z "$(find "$REPO_DIR/packages/generic/nvim" -type f -print -quit 2>/dev/null)" ]] ||
  fail 'retired generic Neovim adapter remains'
[[ ! -e "$REPO_DIR/packages/ubuntu/nvim/.local/share/dotfiles/bin/nvim-record-restore" ]] ||
  fail 'retired restore callback remains'
[[ "$(stat -c %a -- "$RESTORE")" == 755 ]] || fail 'restore helper is not executable'
grep -qxF '"aqua:neovim/neovim" = "0.12.4"' \
  "$REPO_DIR/packages/ubuntu/nvim/.config/mise/conf.d/50-dotfiles-nvim-ubuntu.toml" ||
  fail 'Ubuntu Neovim selector is not exact'
grep -Fq 'install = { missing = vim.env.DOTFILES_NVIM_RESTORING == "1"' \
  "$REPO_DIR/packages/upstream/nvim/.config/nvim/lua/config/lazy.lua" ||
  fail 'ordinary startup can install missing plugins'
grep -Fq 'require("lazy.manage.lock").update = function() end' \
  "$REPO_DIR/packages/upstream/nvim/.config/nvim/lua/config/lazy.lua" ||
  fail 'restore can rewrite the committed lock'
grep -Fq 'vim.opt.relativenumber = true' \
  "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" || fail 'personal option is absent'
pass

make_nvim() {
  local path="$1" version="$2"
  mkdir -p "$(dirname -- "$path")"
  printf '#!/usr/bin/env bash\nprintf "NVIM v%s\\n"\n' "$version" > "$path"
  chmod 0755 "$path"
}

run_area() {
  local home="$1" host="$2" profile="$3" operation="$4" mode=apply binary
  [[ "$operation" != check ]] || mode=check
  [[ "$operation" != remove ]] || mode=remove
  binary="$host/usr/bin/nvim"
  HOME="$home" HOST_ROOT="$host" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=nvim-test SELECTED_PROFILE="$profile" MODE="$mode" DOTFILES_TESTING=1 \
    DOTFILES_TEST_NVIM_BIN="$binary" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/host.sh"
      source "$DOTFILES_DIR/lib/lean_engine.sh"
      source "$DOTFILES_DIR/lib/areas/nvim.sh"
      validate_area_manifest
      if [[ "$MODE" == remove ]]; then remove_nvim
      elif [[ "$MODE" == check ]]; then preflight_nvim
      else preflight_nvim; apply_nvim
      fi
    '
}

# Ubuntu is package-only: lifecycle writes links but no v2 state and never
# changes application-owned data, state, or cache roots.
ubuntu_host="$(make_host nvim-ubuntu linux)"
make_nvim "$ubuntu_host/usr/bin/nvim" 0.12.4
ubuntu_home="$(new_home nvim-ubuntu)"
mkdir -p "$ubuntu_home/.local/share/nvim" "$ubuntu_home/.local/state/nvim" "$ubuntu_home/.cache/nvim"
printf data > "$ubuntu_home/.local/share/nvim/sentinel"
printf state > "$ubuntu_home/.local/state/nvim/sentinel"
printf cache > "$ubuntu_home/.cache/nvim/sentinel"
runtime_before="$(sha256sum "$ubuntu_home"/.local/share/nvim/sentinel "$ubuntu_home"/.local/state/nvim/sentinel "$ubuntu_home"/.cache/nvim/sentinel)"
run_area "$ubuntu_home" "$ubuntu_host" ubuntu apply >/dev/null
[[ -L "$ubuntu_home/.config/nvim/lazy-lock.json" ]] || fail 'Ubuntu lockfile was not deployed'
cmp -s "$ubuntu_home/.config/nvim/lazy-lock.json" "$LOCKFILE" || fail 'deployed lockfile differs from accepted bytes'
[[ ! -e "$ubuntu_home/.local/state/dotfiles/v2/nvim.json" ]] || fail 'package-only Ubuntu Neovim wrote state'
run_area "$ubuntu_home" "$ubuntu_host" ubuntu check >/dev/null
run_area "$ubuntu_home" "$ubuntu_host" ubuntu remove >/dev/null
[[ ! -e "$ubuntu_home/.config/nvim/init.lua" && ! -e "$ubuntu_home/.local/state/dotfiles/v2/nvim.json" ]] ||
  fail 'Ubuntu removal retained managed links or state'
[[ "$(sha256sum "$ubuntu_home"/.local/share/nvim/sentinel "$ubuntu_home"/.local/state/nvim/sentinel "$ubuntu_home"/.cache/nvim/sentinel)" == "$runtime_before" ]] ||
  fail 'ordinary Ubuntu lifecycle changed Neovim runtime data'
pass

# Legacy v1 state is refused by the lean engine and left untouched.
legacy_home="$(new_home nvim-v1)"
mkdir -p "$legacy_home/.local/state/dotfiles/v1"
printf '{}\n' > "$legacy_home/.local/state/dotfiles/v1/nvim.json"
if run_area "$legacy_home" "$ubuntu_host" ubuntu apply >/dev/null 2>"$TEST_ROOT/v1.err"; then
  fail 'legacy Neovim v1 state was accepted'
fi
grep -Fq 'legacy v1 deployment state exists for lean area' "$TEST_ROOT/v1.err" || fail 'v1 refusal was unclear'
[[ "$(< "$legacy_home/.local/state/dotfiles/v1/nvim.json")" == '{}' ]] || fail 'v1 refusal mutated legacy state'
pass

# Native validates both accepted packages and /usr/bin/nvim, preserves baseline
# bytes, and stores only the loader attachment ownership in v2 state.
native_host="$(make_host nvim-native linux omarchy 4.0.1)"
make_nvim "$native_host/usr/bin/nvim" 0.12.5
record_pacman_ownership "$native_host" 'neovim 0.12.5-1' /usr/bin/nvim
record_pacman_ownership "$native_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
native_home="$(new_home nvim-native)"
mkdir -p "$native_home/.config/nvim/plugin"
printf 'require("config.lazy")\n' > "$native_home/.config/nvim/init.lua"
baseline_before="$(sha256sum "$native_home/.config/nvim/init.lua")"
run_area "$native_home" "$native_host" omarchy apply >/dev/null
[[ "$(sha256sum "$native_home/.config/nvim/init.lua")" == "$baseline_before" ]] || fail 'native apply rewrote baseline'
[[ -L "$native_home/.config/dotfiles/nvim/personal.lua" && -f "$native_home/.config/nvim/plugin/dotfiles-personal.lua" ]] ||
  fail 'native personal layer or loader is absent'
state="$native_home/.local/state/dotfiles/v2/nvim.json"
jq -e '.area == "nvim" and .profile == "omarchy" and
  (.attachments | keys) == [".config/nvim/plugin/dotfiles-personal.lua"] and
  .attachments[".config/nvim/plugin/dotfiles-personal.lua"].id == "nvim-native-loader"' "$state" >/dev/null ||
  fail 'native Neovim v2 state is not attachment-only'
run_area "$native_home" "$native_host" omarchy check >/dev/null
mv "$state" "$state.saved"
if run_area "$native_home" "$native_host" omarchy check >/dev/null 2>"$TEST_ROOT/native-missing-state.err"; then
  fail 'missing native ownership state passed check'
fi
grep -Fq './dotfiles.sh apply nvim' "$TEST_ROOT/native-missing-state.err" ||
  fail 'missing native ownership state did not give area-specific repair guidance'
mv "$state.saved" "$state"
rm "$native_home/.config/nvim/plugin/dotfiles-personal.lua"
if run_area "$native_home" "$native_host" omarchy check >/dev/null 2>"$TEST_ROOT/native-missing-loader.err"; then
  fail 'missing refreshed loader passed check'
fi
grep -Fq './dotfiles.sh apply nvim' "$TEST_ROOT/native-missing-loader.err" ||
  fail 'missing native attachment did not give area-specific repair guidance'
run_area "$native_home" "$native_host" omarchy apply >/dev/null
run_area "$native_home" "$native_host" omarchy remove >/dev/null
[[ ! -e "$native_home/.config/nvim/plugin/dotfiles-personal.lua" && ! -e "$state" ]] ||
  fail 'native removal retained loader state'
[[ "$(sha256sum "$native_home/.config/nvim/init.lua")" == "$baseline_before" ]] || fail 'native lifecycle changed baseline'
pass

new_host="$(make_host nvim-native-new linux omarchy 4.0.1)"
make_nvim "$new_host/usr/bin/nvim" 0.13.0+git
record_pacman_ownership "$new_host" 'neovim 1:0.13.0+git-2.1' /usr/bin/nvim
record_pacman_ownership "$new_host" 'omarchy-nvim 2026.9-1' /usr/share/omarchy-nvim
new_home="$(new_home nvim-native-new)"; mkdir -p "$new_home/.config/nvim"
printf 'return {}\n' > "$new_home/.config/nvim/init.lua"
run_area "$new_home" "$new_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-new.err"
grep -Fq 'native Neovim package version is unreviewed' "$TEST_ROOT/native-new.err" ||
  fail 'valid unreviewed native Neovim package did not warn'
grep -Fq 'native omarchy-nvim package version is unreviewed' "$TEST_ROOT/native-new.err" ||
  fail 'valid unreviewed native baseline package did not warn'
pass

reviewed_host="$(make_host nvim-native-reviewed linux omarchy 4.0.1)"
make_nvim "$reviewed_host/usr/bin/nvim" 0.12.4
record_pacman_ownership "$reviewed_host" 'neovim 0.12.4-1' /usr/bin/nvim
record_pacman_ownership "$reviewed_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
reviewed_home="$(new_home nvim-native-reviewed)"; mkdir -p "$reviewed_home/.config/nvim"
printf 'return {}\n' > "$reviewed_home/.config/nvim/init.lua"
run_area "$reviewed_home" "$reviewed_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-reviewed.err"
[[ ! -s "$TEST_ROOT/native-reviewed.err" ]] || fail 'reviewed native Neovim 0.12.4 package warned'
pass

missing_owner_host="$(make_host nvim-native-missing-owner linux omarchy 4.0.1)"
make_nvim "$missing_owner_host/usr/bin/nvim" 0.12.5
record_pacman_ownership "$missing_owner_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
missing_owner_home="$(new_home nvim-native-missing-owner)"; mkdir -p "$missing_owner_home/.config/nvim"
printf 'return {}\n' > "$missing_owner_home/.config/nvim/init.lua"
if run_area "$missing_owner_home" "$missing_owner_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-missing-owner.err"; then
  fail 'missing native Neovim package owner passed validation'
fi
grep -Fq "found 'no package owner'" "$TEST_ROOT/native-missing-owner.err" ||
  fail 'missing native package owner refusal was unclear'
pass

wrong_owner_host="$(make_host nvim-native-wrong-owner linux omarchy 4.0.1)"
make_nvim "$wrong_owner_host/usr/bin/nvim" 0.12.5
record_pacman_ownership "$wrong_owner_host" 'not-neovim 0.12.5-1' /usr/bin/nvim
record_pacman_ownership "$wrong_owner_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
wrong_owner_home="$(new_home nvim-native-wrong-owner)"; mkdir -p "$wrong_owner_home/.config/nvim"
printf 'return {}\n' > "$wrong_owner_home/.config/nvim/init.lua"
if run_area "$wrong_owner_home" "$wrong_owner_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-wrong-owner.err"; then
  fail 'wrong native Neovim package owner passed validation'
fi
grep -Fq 'must be owned by neovim with valid version metadata' "$TEST_ROOT/native-wrong-owner.err" ||
  fail 'native package owner refusal was unclear'
pass

bad_metadata_host="$(make_host nvim-native-bad-metadata linux omarchy 4.0.1)"
make_nvim "$bad_metadata_host/usr/bin/nvim" 0.12.5
record_pacman_ownership "$bad_metadata_host" 'neovim rolling-1' /usr/bin/nvim
record_pacman_ownership "$bad_metadata_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
bad_metadata_home="$(new_home nvim-native-bad-metadata)"; mkdir -p "$bad_metadata_home/.config/nvim"
printf 'return {}\n' > "$bad_metadata_home/.config/nvim/init.lua"
if run_area "$bad_metadata_home" "$bad_metadata_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-bad-metadata.err"; then
  fail 'invalid native Neovim package metadata passed validation'
fi
grep -Fq 'valid version metadata' "$TEST_ROOT/native-bad-metadata.err" || fail 'invalid metadata refusal was unclear'
pass

mismatch_host="$(make_host nvim-native-mismatch linux omarchy 4.0.1)"
make_nvim "$mismatch_host/usr/bin/nvim" 0.12.6
record_pacman_ownership "$mismatch_host" 'neovim 0.12.5-1' /usr/bin/nvim
record_pacman_ownership "$mismatch_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
mismatch_home="$(new_home nvim-native-mismatch)"; mkdir -p "$mismatch_home/.config/nvim"
printf 'return {}\n' > "$mismatch_home/.config/nvim/init.lua"
if run_area "$mismatch_home" "$mismatch_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-mismatch.err"; then
  fail 'native Neovim package/runtime mismatch passed validation'
fi
grep -Fq 'does not match package version' "$TEST_ROOT/native-mismatch.err" || fail 'runtime mismatch refusal was unclear'
pass

bad_runtime_host="$(make_host nvim-native-bad-runtime linux omarchy 4.0.1)"
mkdir -p "$bad_runtime_host/usr/bin"
printf '#!/usr/bin/env bash\nprintf "NVIM v0.12.5 \\n"\n' > "$bad_runtime_host/usr/bin/nvim"
chmod 0755 "$bad_runtime_host/usr/bin/nvim"
record_pacman_ownership "$bad_runtime_host" 'neovim 0.12.5-1' /usr/bin/nvim
record_pacman_ownership "$bad_runtime_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
bad_runtime_home="$(new_home nvim-native-bad-runtime)"; mkdir -p "$bad_runtime_home/.config/nvim"
printf 'return {}\n' > "$bad_runtime_home/.config/nvim/init.lua"
if run_area "$bad_runtime_home" "$bad_runtime_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-bad-runtime.err"; then
  fail 'native Neovim runtime with trailing version garbage passed validation'
fi
grep -Fq 'returned an invalid version' "$TEST_ROOT/native-bad-runtime.err" || fail 'invalid runtime refusal was unclear'
pass

suffix_mismatch_host="$(make_host nvim-native-suffix-mismatch linux omarchy 4.0.1)"
make_nvim "$suffix_mismatch_host/usr/bin/nvim" 0.12.5garbage
record_pacman_ownership "$suffix_mismatch_host" 'neovim 0.12.5-1' /usr/bin/nvim
record_pacman_ownership "$suffix_mismatch_host" 'omarchy-nvim 2026.8.13-1' /usr/share/omarchy-nvim
suffix_mismatch_home="$(new_home nvim-native-suffix-mismatch)"; mkdir -p "$suffix_mismatch_home/.config/nvim"
printf 'return {}\n' > "$suffix_mismatch_home/.config/nvim/init.lua"
if run_area "$suffix_mismatch_home" "$suffix_mismatch_host" omarchy apply >/dev/null 2>"$TEST_ROOT/native-suffix-mismatch.err"; then
  fail 'native Neovim runtime suffix mismatch passed validation'
fi
grep -Fq 'does not match package version' "$TEST_ROOT/native-suffix-mismatch.err" ||
  fail 'runtime suffix mismatch refusal was unclear'
pass

unowned_baseline_host="$(make_host nvim-native-unowned-baseline linux omarchy 4.0.1)"
make_nvim "$unowned_baseline_host/usr/bin/nvim" 0.12.5
record_pacman_ownership "$unowned_baseline_host" 'neovim 0.12.5-1' /usr/bin/nvim
unowned_baseline_home="$(new_home nvim-native-unowned-baseline)"
mkdir -p "$unowned_baseline_home/.config/nvim"
printf 'return {}\n' > "$unowned_baseline_home/.config/nvim/init.lua"
if run_area "$unowned_baseline_home" "$unowned_baseline_host" omarchy apply \
  >/dev/null 2>"$TEST_ROOT/native-unowned-baseline.err"; then
  fail 'unowned native Neovim baseline passed validation'
fi
grep -Fq 'must be owned by omarchy-nvim with valid version metadata' "$TEST_ROOT/native-unowned-baseline.err" ||
  fail 'native baseline ownership refusal was unclear'
pass

# Explicit restore obtains exactly the lockfile lazy.nvim commit, enables only
# the restoring context, invokes Lazy restore, and writes no deployment state.
restore_home="$(new_home nvim-restore)"
mkdir -p "$restore_home/.config/nvim" "$restore_home/.local/state/dotfiles/v2"
cp "$LOCKFILE" "$restore_home/.config/nvim/lazy-lock.json"
printf 'state sentinel\n' > "$restore_home/.local/state/dotfiles/v2/sentinel"
state_before="$(sha256sum "$restore_home/.local/state/dotfiles/v2/sentinel")"
lazy_repo="$TEST_ROOT/lazy-repo"
mkdir "$lazy_repo"
git -C "$lazy_repo" init -q
git -C "$lazy_repo" -c user.name=test -c user.email=test@example.invalid commit --allow-empty -qm locked
fixture_commit="$(git -C "$lazy_repo" rev-parse HEAD)"
jq --arg commit "$fixture_commit" '."lazy.nvim".commit = $commit' \
  "$restore_home/.config/nvim/lazy-lock.json" > "$restore_home/.config/nvim/lazy-lock.new"
mv "$restore_home/.config/nvim/lazy-lock.new" "$restore_home/.config/nvim/lazy-lock.json"
restore_lock_before="$(sha256sum "$restore_home/.config/nvim/lazy-lock.json")"
cat > "$TEST_ROOT/restore-nvim" <<'SCRIPT'
#!/usr/bin/env bash
[[ "${DOTFILES_NVIM_RESTORING:-}" == 1 ]] || exit 91
[[ "$*" == *'+Lazy! restore'* ]] || exit 92
printf '%s\n' "$*" > "$RESTORE_REPORT"
SCRIPT
chmod 0755 "$TEST_ROOT/restore-nvim"
HOME="$restore_home" DOTFILES_TESTING=1 DOTFILES_NVIM_LAZY_REPOSITORY="$lazy_repo" \
  DOTFILES_NVIM_COMMITTED_LOCKFILE="$restore_home/.config/nvim/lazy-lock.json" \
  DOTFILES_NVIM_EXECUTABLE="$TEST_ROOT/restore-nvim" RESTORE_REPORT="$TEST_ROOT/restore.report" "$RESTORE" >/dev/null
[[ "$(git -C "$restore_home/.local/share/nvim/lazy/lazy.nvim" rev-parse HEAD)" == "$fixture_commit" ]] ||
  fail 'restore did not obtain exact lazy.nvim commit'
[[ "$(< "$TEST_ROOT/restore.report")" == *'+Lazy! restore'* ]] || fail 'restore did not invoke ordinary Lazy restore'
[[ "$(sha256sum "$restore_home/.config/nvim/lazy-lock.json")" == "$restore_lock_before" ]] || fail 'restore rewrote lockfile'
[[ "$(sha256sum "$restore_home/.local/state/dotfiles/v2/sentinel")" == "$state_before" &&
  "$(find "$restore_home/.local/state/dotfiles/v2" -mindepth 1 -maxdepth 1 -printf '%f\n')" == sentinel ]] ||
  fail 'restore wrote deployment state'
pass

# A real isolated startup with an existing locked lazy checkout cannot invoke a
# network command or install missing plugins.
command -v nvim >/dev/null || fail 'Neovim is required for isolated startup acceptance'
startup_home="$(new_home nvim-startup)"
config="$startup_home/.config/nvim"; data="$startup_home/.local/share/nvim"
mkdir -p "$config" "$data/lazy/lazy.nvim/lua/lazy/core" "$startup_home/.config/dotfiles/nvim"
cp -a "$REPO_DIR/packages/upstream/nvim/.config/nvim/." "$config/"
cp -a "$REPO_DIR/packages/ubuntu/nvim/.config/nvim/." "$config/"
cp "$REPO_DIR/packages/ubuntu/nvim/.config/dotfiles/nvim/ubuntu.lua" "$startup_home/.config/dotfiles/nvim/ubuntu.lua"
cp "$REPO_DIR/packages/common/nvim/.config/dotfiles/nvim/personal.lua" "$startup_home/.config/dotfiles/nvim/personal.lua"
cat > "$data/lazy/lazy.nvim/lua/lazy/init.lua" <<'LUA'
local M = {}
function M.setup(opts)
  assert(opts.install.missing == false, "ordinary startup installs missing plugins")
  assert(opts.checker.enabled == false, "ordinary startup enables checker")
  vim.fn.writefile({ "offline" }, vim.env.NVIM_TEST_REPORT)
end
return M
LUA
cat > "$data/lazy/lazy.nvim/lua/lazy/core/config.lua" <<'LUA'
return { plugins = {} }
LUA
git -C "$data/lazy/lazy.nvim" init -q
git -C "$data/lazy/lazy.nvim" add .
git -C "$data/lazy/lazy.nvim" -c user.name=test -c user.email=test@example.invalid commit -qm locked
startup_commit="$(git -C "$data/lazy/lazy.nvim" rev-parse HEAD)"
jq --arg commit "$startup_commit" '."lazy.nvim".commit = $commit' "$config/lazy-lock.json" > "$config/lazy-lock.new"
mv "$config/lazy-lock.new" "$config/lazy-lock.json"
install_network_sentinels "$startup_home" with-git
HOME="$startup_home" PATH="$startup_home/fake-bin:$PATH" NVIM_TEST_REPORT="$TEST_ROOT/startup.report" \
  nvim --headless -u "$config/init.lua" -i NONE +qa >/dev/null 2>"$TEST_ROOT/startup.err" || {
    TEST_OUTPUT="$(< "$TEST_ROOT/startup.err")"; fail 'isolated ordinary Neovim startup failed';
  }
[[ "$(< "$TEST_ROOT/startup.report")" == offline && ! -e "$startup_home/network-attempted" ]] ||
  fail 'ordinary startup attempted network or missing-plugin installation'
pass

printf 'PASS: Neovim lean checks (%d groups)\n' "$TEST_COUNT"
