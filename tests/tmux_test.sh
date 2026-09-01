#!/usr/bin/env bash
# Focused tmux validation-only and Ubuntu package-only lifecycle tests.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

test_bin="$TEST_ROOT/bin"
install_fake_stow "$test_bin"

make_fake_tmux() {
  local path="$1" version="$2"
  cat > "$path" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "\$*" >> "${path}.trace"
if [[ "\${1:-}" == -V ]]; then printf 'tmux $version\n'; exit 0; fi
case " \$* " in
  *' new-session '*) [[ -f "\${6:-}" || -f "\${5:-}" || -f "\${4:-}" ]] || exit 2 ;;
  *' show-options -gv prefix2 '*) printf 'C-b\n' ;;
  *' show-options -gv prefix '*) printf 'C-Space\n' ;;
  *' show-options -gv default-terminal '*) printf 'tmux-256color\n' ;;
  *' list-keys -T prefix '*) printf 'bind-key -T prefix ? display-popup less -R .config/dotfiles/tmux/keybindings.txt\n' ;;
  *' kill-server '*) : ;;
  *) exit 3 ;;
esac
SCRIPT
  chmod 0755 "$path"
}

run_tmux_area() {
  local home="$1" profile="$2" operation="$3" host_root="$4" binary="$5" owner="${6:-}"
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    HOST_ROOT="$host_root" SCRIPT_NAME=tmux-test SELECTED_PROFILE="$profile" MODE="$operation" \
    DOTFILES_TESTING=1 DOTFILES_TEST_TMUX_BIN="$binary" DOTFILES_TEST_TMUX_OWNER="$owner" \
    PATH="$test_bin:/usr/bin:/bin" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/host.sh"
      source "$DOTFILES_DIR/lib/lean_engine.sh"
      source "$DOTFILES_DIR/lib/areas/tmux.sh"
      validate_area_manifest
      case "$MODE" in
        check) preflight_tmux ;;
        apply) preflight_tmux; apply_tmux ;;
        remove) remove_tmux ;;
      esac
    '
}

# The immutable baseline and adapter are separate: Ubuntu changes only the help
# binding and uses repository-owned static text.
baseline="$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf"
adapter="$REPO_DIR/packages/ubuntu/tmux/.config/dotfiles/tmux/ubuntu.conf"
dispatcher="$REPO_DIR/packages/ubuntu/tmux/.config/tmux/tmux.conf"
selector="$REPO_DIR/packages/ubuntu/tmux/.config/mise/conf.d/50-dotfiles-tmux-ubuntu.toml"
grep -qxF 'set -g prefix C-Space' "$baseline" || fail 'baseline lost C-Space'
grep -qxF 'set -g prefix2 C-b' "$baseline" || fail 'baseline lost C-b'
grep -qxF 'set -g default-terminal "tmux-256color"' "$baseline" || fail 'baseline lost tmux-256color'
grep -qxF 'source-file ~/.config/dotfiles/upstream/tmux/tmux.conf' "$dispatcher" || fail 'dispatcher lost baseline source'
grep -qxF 'source-file ~/.config/dotfiles/tmux/ubuntu.conf' "$dispatcher" || fail 'dispatcher lost adapter source'
grep -Fq 'display-popup' "$adapter" || fail 'portable popup is absent'
grep -Fq 'keybindings.txt' "$adapter" || fail 'portable popup does not use static help'
! grep -Fq 'omarchy-menu-tmux-keybindings' "$adapter" || fail 'adapter invokes an Omarchy-only command'
grep -qxF '"aqua:tmux/tmux-builds" = "3.7c"' "$selector" || fail 'selector is not exact'
pass

# Native apply/check/remove validate exact package/runtime/config behavior and
# do not call Stow or create either state namespace.
native_host="$(make_system_fixture tmux-native)"
native_bin="$native_host/usr/bin/tmux"
make_fake_tmux "$native_bin" 3.7c
record_pacman_ownership "$native_host" 'tmux 3.7_c-1' /usr/bin/tmux
home="$(new_home native)"
mkdir -p "$home/.config/tmux" "$home/.tmux/plugins" "$home/.tmux/resurrect"
cp "$baseline" "$home/.config/tmux/tmux.conf"
chmod 0640 "$home/.config/tmux/tmux.conf"
printf 'plugin\n' > "$home/.tmux/plugins/data"
printf 'session\n' > "$home/.tmux/resurrect/data"
cp -a "$home" "$TEST_ROOT/native-before"
: > "$FAKE_STOW_TRACE"
run_tmux_area "$home" omarchy check "$native_host" "$native_bin" >/dev/null
diff --no-dereference -r "$home" "$TEST_ROOT/native-before" >/dev/null || fail 'native check mutated HOME'
run_tmux_area "$home" omarchy apply "$native_host" "$native_bin" >/dev/null
run_tmux_area "$home" omarchy remove "$native_host" "$native_bin" >/dev/null
diff --no-dereference -r "$home" "$TEST_ROOT/native-before" >/dev/null || fail 'native lifecycle mutated HOME'
[[ ! -s "$FAKE_STOW_TRACE" && ! -e "$home/.local/state/dotfiles" ]] || fail 'native lifecycle invoked Stow or wrote state'
pass

# Native package, runtime, baseline, owner, and mode drift all refuse with
# concise refresh/reinstall guidance.
capture_native_failure() {
  set +e
  TEST_OUTPUT="$(run_tmux_area "$home" omarchy check "$native_host" "$native_bin" 2>&1)"
  TEST_RC=$?
  set -e
  ((TEST_RC != 0)) || fail 'native drift unexpectedly passed'
  assert_contains "$TEST_OUTPUT" 'refresh tmux or reinstall tmux'
}
printf 'drift\n' >> "$home/.config/tmux/tmux.conf"
capture_native_failure
cp "$baseline" "$home/.config/tmux/tmux.conf"
chmod 0666 "$home/.config/tmux/tmux.conf"
capture_native_failure
chmod 0644 "$home/.config/tmux/tmux.conf"
printf '/usr/bin/tmux\ttmux 3.7_b-1\n' > "$native_host/var/lib/dotfiles-test/pacman-owners.tsv"
capture_native_failure
pass

# Any legacy tmux v1 state refuses before validation or mutation.
printf '/usr/bin/tmux\ttmux 3.7_c-1\n' > "$native_host/var/lib/dotfiles-test/pacman-owners.tsv"
mkdir -p "$home/.local/state/dotfiles/v1"
printf '{}\n' > "$home/.local/state/dotfiles/v1/tmux.json"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" omarchy apply "$native_host" "$native_bin" 2>&1)"; TEST_RC=$?
set -e
((TEST_RC != 0)) || fail 'legacy tmux state was accepted'
assert_contains "$TEST_OUTPUT" 'legacy v1 deployment state exists for lean area'
rm -rf "$home/.local"
pass

# Ubuntu is package-only and state-free. Check is non-mutating; apply/remove
# touch only exact links and preserve user/application-owned tmux data.
ubuntu_host="$(make_system_fixture tmux-ubuntu)"
ubuntu_bin="$ubuntu_host/usr/bin/tmux"
make_fake_tmux "$ubuntu_bin" 3.5
home="$(new_home ubuntu)"
mkdir -p "$home/.tmux/plugins" "$home/.tmux/resurrect" "$home/.local/state/application"
printf 'plugin\n' > "$home/.tmux/plugins/data"
printf 'session\n' > "$home/.tmux/resurrect/data"
printf 'app\n' > "$home/.local/state/application/data"
cp -a "$home" "$TEST_ROOT/ubuntu-before"
: > "$FAKE_STOW_TRACE"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" ubuntu check "$ubuntu_host" "$ubuntu_bin" distro:tmux 2>&1)"; TEST_RC=$?
set -e
((TEST_RC != 0)) || fail 'unapplied Ubuntu check unexpectedly converged'
diff --no-dereference -r "$home" "$TEST_ROOT/ubuntu-before" >/dev/null || fail 'Ubuntu check mutated HOME'
run_tmux_area "$home" ubuntu apply "$ubuntu_host" "$ubuntu_bin" distro:tmux >/dev/null
[[ -L "$home/.config/tmux/tmux.conf" && -L "$home/.config/dotfiles/upstream/tmux/tmux.conf" &&
  -L "$home/.config/mise/conf.d/50-dotfiles-tmux-ubuntu.toml" ]] || fail 'Ubuntu apply did not deploy the final closure'
[[ ! -e "$home/.local/state/dotfiles/v2/tmux.json" ]] || fail 'Ubuntu package-only apply wrote state'
run_tmux_area "$home" ubuntu check "$ubuntu_host" "$ubuntu_bin" distro:tmux >/dev/null
run_tmux_area "$home" ubuntu remove "$ubuntu_host" "$ubuntu_bin" distro:tmux >/dev/null
[[ ! -e "$home/.config/tmux/tmux.conf" && "$(< "$home/.tmux/plugins/data")" == plugin &&
  "$(< "$home/.tmux/resurrect/data")" == session && "$(< "$home/.local/state/application/data")" == app ]] ||
  fail 'Ubuntu remove changed retained tmux/application data'
pass

# An old distro runtime is rejected with the exact selector; a non-distro
# selected runtime must be the exact 3.7c fallback.
old_bin="$ubuntu_host/usr/bin/tmux"
make_fake_tmux "$old_bin" 3.4
set +e
TEST_OUTPUT="$(run_tmux_area "$home" ubuntu check "$ubuntu_host" "$old_bin" distro:tmux 2>&1)"; TEST_RC=$?
set -e
((TEST_RC != 0)) || fail 'Ubuntu tmux 3.4 was accepted'
assert_contains "$TEST_OUTPUT" 'mise install aqua:tmux/tmux-builds@3.7c'
fallback="$TEST_ROOT/mise-tmux"
make_fake_tmux "$fallback" 3.7c
run_tmux_area "$home" ubuntu apply "$ubuntu_host" "$fallback" mise >/dev/null
run_tmux_area "$home" ubuntu remove "$ubuntu_host" "$fallback" mise >/dev/null
make_fake_tmux "$fallback" 3.7b
set +e
TEST_OUTPUT="$(run_tmux_area "$home" ubuntu check "$ubuntu_host" "$fallback" mise 2>&1)"; TEST_RC=$?
set -e
((TEST_RC != 0)) || fail 'non-exact mise tmux was accepted'
assert_contains "$TEST_OUTPUT" 'mise install aqua:tmux/tmux-builds@3.7c'
pass

# Use a real installed parser whenever the current direct runtime meets the
# accepted minimum; fake-runtime coverage remains deterministic otherwise.
real_tmux="$(type -P tmux 2>/dev/null || true)"
real_version="$("$real_tmux" -V 2>/dev/null || true)"
if [[ "$real_tmux" == /usr/bin/tmux && "$real_version" =~ ^tmux[[:space:]]+([0-9]+)\.([0-9]+)[a-z]?$ ]] &&
  ((10#${BASH_REMATCH[1]} > 3 || (10#${BASH_REMATCH[1]} == 3 && 10#${BASH_REMATCH[2]} >= 5))); then
  home="$(new_home real-parser)"
  HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=tmux-test \
    SELECTED_PROFILE=ubuntu TMUX_BINARY="$real_tmux" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/areas/tmux.sh"
      validate_tmux_parse
    '
  pass
else
  printf 'SKIP: real installed tmux >=3.5 parser unavailable (found: %s)\n' "${real_version:-missing}"
fi

printf 'PASS: %s focused tmux test groups\n' "$TEST_COUNT"
