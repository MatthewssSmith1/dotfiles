#!/usr/bin/env bash
# Focused lean Bash package, startup, attachment, and lifecycle tests.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
export PATH="$fake_bin:/usr/bin:/bin"
export FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
: > "$FAKE_STOW_TRACE"

run_bash_area() {
  local home="$1" profile="$2" operation="$3"
  HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=shell-test \
    SELECTED_PROFILE="$profile" MODE="$operation" PATH="$PATH" FAKE_STOW_TRACE="$FAKE_STOW_TRACE" \
    FAKE_LOGIN_SHELL="${FAKE_LOGIN_SHELL:-/usr/bin/bash}" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HIDE_COMMANDS="${DOTFILES_TEST_HIDE_COMMANDS:-}" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/lean_engine.sh"
      source "$DOTFILES_DIR/lib/areas/bash.sh"
      validate_area_manifest
      case "$MODE" in
        apply) preflight_bash; apply_bash ;;
        check) preflight_bash ;;
        remove) remove_bash ;;
      esac
    '
}

make_initializer() {
  local name="$1" expected="$2" marker="$3"
  printf '#!/usr/bin/env bash\n[[ "${MISE_OFFLINE:-}" == 1 && "$*" == %q ]] || exit 2\nprintf "%%s\\n" %q\n' "$expected" \
    "printf '%s\\n' '$marker' >> \"\$INIT_TRACE\"" > "$fake_bin/$name"
  chmod 0755 "$fake_bin/$name"
}

make_initializer mise 'activate bash' mise-init
make_initializer starship 'init bash' starship-init
make_initializer zoxide 'init bash' zoxide-init
make_initializer wt 'config shell init bash' worktrunk-init
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/fzf"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/eza"
printf '#!/usr/bin/env bash\nprintf "test:x:1000:1000::/home/test:%%s\\n" "$FAKE_LOGIN_SHELL"\n' > "$fake_bin/getent"
chmod 0755 "$fake_bin/fzf" "$fake_bin/eza" "$fake_bin/getent"

# The repository contains only the native/common and Ubuntu Bash payloads.
[[ -z "$(find "$REPO_DIR/packages/generic/bash" "$REPO_DIR/packages/wsl" "$REPO_DIR/packages/common/zsh" \
  -type f -print -quit 2>/dev/null)" ]] ||
  fail 'retired generic, WSL, or zsh payload remains'
for file in \
  "$REPO_DIR/packages/common/bash/.config/dotfiles/bash/rc.bash" \
  "$REPO_DIR/packages/common/bash/.config/dotfiles/bash/integrations.bash" \
  "$REPO_DIR/packages/common/bash/.config/dotfiles/bash/personal.bash" \
  "$REPO_DIR/packages/ubuntu/bash/.config/dotfiles/bash/ubuntu.bash" \
  "$REPO_DIR/packages/ubuntu/bash/.config/dotfiles/bash/env.bash" \
  "$REPO_DIR/packages/ubuntu/bash/.config/dotfiles/bash/init.bash"; do
  bash -n "$file" || fail "invalid Bash syntax: $file"
done
selector="$REPO_DIR/packages/ubuntu/bash/.config/mise/conf.d/40-dotfiles-bash-ubuntu.toml"
grep -qxF '"aqua:starship/starship" = "1.26.0"' "$selector" || fail 'Ubuntu Starship selector is not exact'
! grep -RqsE '^[[:space:]]*node[[:space:]]*=' "$REPO_DIR/packages/common/bash" "$REPO_DIR/packages/ubuntu/bash" ||
  fail 'Bash selects Node'
! grep -Fq "alias c=" "$REPO_DIR/packages/common/bash/.config/dotfiles/bash/personal.bash" ||
  fail 'common Bash duplicates a native v4 alias'
pass

# Ubuntu Bash login startup must remain a manually owned host prerequisite.
home="$TEST_ROOT/home-login-missing"
mkdir "$home"
printf ':\n' > "$home/.bashrc"
set +e
output="$(run_bash_area "$home" ubuntu apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 && ! -e "$home/.local/state/dotfiles/v2/bash.json" ]] ||
  fail 'missing Ubuntu login startup did not stop before mutation'
assert_contains "$output" 'manually restore a host-owned ~/.profile that sources ~/.bashrc'
for file in .profile .bash_profile .bash_login; do
  [[ ! -e "$home/$file" && ! -L "$home/$file" ]] || fail "Bash preflight created $file"
done
for file in .profile .bash_profile .bash_login; do
  candidate="$TEST_ROOT/home-login-${file#.}"
  mkdir "$candidate"
  printf ':\n' > "$candidate/.bashrc"
  printf '. "$HOME/.bashrc"\n' > "$candidate/$file"
  run_bash_area "$candidate" ubuntu apply
done
home="$TEST_ROOT/home-login-non-bash"
mkdir "$home"
printf ':\n' > "$home/.bashrc"
FAKE_LOGIN_SHELL=/bin/sh run_bash_area "$home" ubuntu apply
pass

# Ubuntu deploys the reviewed portable closure, initializes each guarded tool
# offline in order, and sources the host-local layer last exactly once.
home="$TEST_ROOT/home-ubuntu"
mkdir -p "$home/.config/dotfiles/local"
printf ': # host baseline without newline' > "$home/.bashrc"
chmod 0640 "$home/.bashrc"
cp -a "$home/.bashrc" "$TEST_ROOT/ubuntu.original"
printf '. "$HOME/.bashrc"\n' > "$home/.profile"
cp -a "$home/.profile" "$TEST_ROOT/ubuntu.profile.original"
printf 'host_local_function() { :; }\n' > "$home/.config/dotfiles/local/bash.sh"
run_bash_area "$home" ubuntu apply
state="$home/.local/state/dotfiles/v2/bash.json"
jq -e '.profile == "ubuntu" and .area == "bash" and (.attachments | keys) == [".bashrc"]' "$state" >/dev/null ||
  fail 'Ubuntu Bash ownership state is not exact'
for path in \
  .config/dotfiles/bash/ubuntu.bash .config/dotfiles/upstream/bash/shell \
  .config/starship.toml .config/mise/conf.d/40-dotfiles-bash-ubuntu.toml \
  .local/share/dotfiles/bin/dotfiles-secret; do
  [[ -L "$home/$path" ]] || fail "Ubuntu Bash closure omitted $path"
done
[[ "$(grep -cF '# >>> dotfiles managed bash >>>' "$home/.bashrc")" == 1 ]] || fail 'managed Bash source block is not singular'
: > "$home/trace"; : > "$home/init-trace"
HOME="$home" PATH="$PATH" TERM=xterm INIT_TRACE="$home/init-trace" DOTFILES_BASH_TRACE="$home/trace" \
  MISE_OFFLINE=1 bash --noprofile --norc -i -c 'source "$HOME/.bashrc"; source "$HOME/.bashrc"; declare -F tdl host_local_function >/dev/null' \
  >/dev/null 2> "$home/stderr"
expected_trace=$'ubuntu\nenvironment\nupstream-shell\nupstream-aliases\nupstream-tmux\nmise\nstarship\nzoxide\nfzf\ninputrc\nworktrunk\npersonal\nhost-local'
[[ "$(< "$home/trace")" == "$expected_trace" ]] || {
  TEST_OUTPUT="$(< "$home/trace")"
  fail 'Ubuntu Bash load order or exactly-once guard changed'
}
[[ "$(< "$home/init-trace")" == $'mise-init\nstarship-init\nzoxide-init\nworktrunk-init' ]] ||
  fail 'guarded initializer order changed'
pass

# Interactive OpenCode defaults to personal when its optional launcher exists
# and otherwise falls back to the native PATH executable.
mkdir -p "$home/native-bin"
printf '#!/usr/bin/env bash\nprintf "native"\nprintf "<%%s>" "$@"\n' > "$home/native-bin/opencode"
printf '#!/usr/bin/env bash\nprintf "work"\nprintf "<%%s>" "$@"\n' > "$home/native-bin/opencode-work"
chmod 0755 "$home/native-bin/opencode" "$home/native-bin/opencode-work"
output="$(HOME="$home" PATH="$home/native-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; opencode "two words"' 2>/dev/null)"
[[ "$output" == 'native<two words>' ]] || fail 'OpenCode Bash fallback changed native arguments'
mkdir -p "$home/.local/share/dotfiles/bin"
printf '#!/usr/bin/env bash\nprintf "helper"\nprintf "<%%s>" "$@"\n' > "$home/.local/share/dotfiles/bin/opencode-launch"
chmod 0755 "$home/.local/share/dotfiles/bin/opencode-launch"
output="$(HOME="$home" PATH="$home/native-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; opencode literal' 2>/dev/null)"
[[ "$output" == 'helper<personal><literal>' ]] || fail 'plain OpenCode did not select personal'
output="$(HOME="$home" PATH="$home/native-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; alias c="opencode --auto"; eval '\''c "two words"'\''' 2>/dev/null)"
[[ "$output" == 'helper<personal><--auto><two words>' ]] || fail 'native c alias did not route through personal OpenCode'
output="$(HOME="$home" PATH="$home/native-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; opencode-work literal' 2>/dev/null)"
[[ "$output" == 'work<literal>' ]] || fail 'OpenCode Bash function intercepted the named work launcher'
set +e
HOME="$home" PATH="$home/native-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; bash --noprofile --norc -c "declare -F opencode >/dev/null"' \
  >/dev/null 2>&1
status=$?
set -e
((status != 0)) || fail 'OpenCode Bash function was exported to child shells'
rm "$home/.local/share/dotfiles/bin/opencode-launch"
mkdir -p "$home/.config/dotfiles/opencode" "$home/production-bin"
ln -s "$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/personal.jsonc" \
  "$home/.config/dotfiles/opencode/personal.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.config/dotfiles/opencode/tui.jsonc" \
  "$home/.config/dotfiles/opencode/tui.jsonc"
ln -s "$REPO_DIR/packages/common/opencode/.local/share/dotfiles/bin/opencode-launch" \
  "$home/.local/share/dotfiles/bin/opencode-launch"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$OPENCODE_CONFIG" "$OPENCODE_TUI_CONFIG"\nprintf "<%%s>" "$@"\n' > "$home/production-bin/opencode"
chmod 0755 "$home/production-bin/opencode"
output="$(HOME="$home" PATH="$home/production-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; opencode literal' 2>/dev/null)"
[[ "$output" == "$home/.config/dotfiles/opencode/personal.jsonc"$'\n'"$home/.config/dotfiles/opencode/tui.jsonc"$'\n<literal>' ]] ||
  fail 'interactive OpenCode did not compose with the production launcher'
rm "$home/.local/share/dotfiles/bin/opencode-launch"
output="$(HOME="$home" PATH="$home/native-bin:$PATH" TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"; opencode literal' 2>/dev/null)"
[[ "$output" == 'native<literal>' ]] || fail 'OpenCode removal fallback did not restore native behavior'
pass

# Noninteractive and missing-tool startup remain silent and side-effect free.
: > "$home/trace"
HOME="$home" PATH=/usr/bin:/bin DOTFILES_BASH_TRACE="$home/trace" bash --noprofile --norc -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"' > "$home/noninteractive.out" 2> "$home/noninteractive.err"
[[ ! -s "$home/trace" && ! -s "$home/noninteractive.out" && ! -s "$home/noninteractive.err" ]] ||
  fail 'noninteractive dispatcher changed shell state or emitted output'
HOME="$home" PATH=/usr/bin:/bin TERM=dumb bash --noprofile --norc -i -c \
  'source "$HOME/.config/dotfiles/bash/rc.bash"' > "$home/missing.out" 2> "$home/missing.err"
[[ ! -s "$home/missing.out" ]] || fail 'missing guarded tools emitted stdout'
case "$(< "$home/missing.err")" in ''|bash:\ cannot\ set\ terminal\ process\ group*) ;; *) fail 'missing guarded tools emitted diagnostics' ;; esac
pass

# Ubuntu check gives an exact manual selector when Starship is absent.
set +e
DOTFILES_TEST_HIDE_COMMANDS=starship
output="$(run_bash_area "$home" ubuntu check 2>&1)"
status=$?
unset DOTFILES_TEST_HIDE_COMMANDS
set -e
[[ "$status" != 0 ]] || fail 'Ubuntu check accepted missing Starship'
assert_contains "$output" 'mise install aqua:starship/starship@1.26.0'
run_bash_area "$home" ubuntu check
pass

# Removal restores the host file bytes/mode and removes only managed links and state.
run_bash_area "$home" ubuntu remove
assert_same "$home/.bashrc" "$TEST_ROOT/ubuntu.original"
assert_same "$home/.profile" "$TEST_ROOT/ubuntu.profile.original"
[[ "$(stat -c %a -- "$home/.bashrc")" == 640 && ! -e "$state" &&
  ! -e "$home/.config/dotfiles/bash/rc.bash" && -f "$home/.config/dotfiles/local/bash.sh" ]] ||
  fail 'Ubuntu Bash removal did not preserve host ownership'
[[ "$(HOME="$home" PATH="$home/native-bin:$PATH" bash --noprofile --norc -c 'type -t opencode')" == file ]] ||
  fail 'Bash removal did not leave native OpenCode resolution'
pass

# Native Omarchy receives only the common payload, preserves v4 aliases, and
# recovers when a package refresh replaces the complete host-owned .bashrc.
home="$TEST_ROOT/home-native"
mkdir "$home"
printf 'alias c=native-c\nprintf native >> "$HOME/native-trace"\n' > "$home/.bashrc"
run_bash_area "$home" omarchy apply
[[ -L "$home/.config/dotfiles/bash/rc.bash" && ! -e "$home/.config/starship.toml" &&
  ! -e "$home/.config/dotfiles/bash/ubuntu.bash" ]] || fail 'native Bash deployed a portable baseline'
HOME="$home" PATH=/usr/bin:/bin bash --noprofile --norc -i -c 'source "$HOME/.bashrc"; alias c' > "$home/native.out" 2>/dev/null
assert_contains "$(< "$home/native.out")" "alias c='native-c'"
printf 'printf refreshed >> "$HOME/native-trace"' > "$home/.bashrc"
chmod 0600 "$home/.bashrc"
run_bash_area "$home" omarchy apply
printf 'printf refreshed >> "$HOME/native-trace"' > "$TEST_ROOT/native.refreshed"
chmod 0600 "$TEST_ROOT/native.refreshed"
run_bash_area "$home" omarchy remove
assert_same "$home/.bashrc" "$TEST_ROOT/native.refreshed"
[[ "$(stat -c %a -- "$home/.bashrc")" == 600 ]] || fail 'native refresh removal changed host mode'
pass

# Partial or modified managed blocks refuse before package mutation.
home="$TEST_ROOT/home-malformed"
mkdir "$home"
printf '# >>> dotfiles managed bash >>>\npartial\n' > "$home/.bashrc"
printf '. "$HOME/.bashrc"\n' > "$home/.profile"
set +e
output="$(run_bash_area "$home" ubuntu apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 && ! -e "$home/.local/state/dotfiles/v2/bash.json" ]] || fail 'malformed source block was adopted'
assert_contains "$output" 'partial, malformed'
pass

printf 'PASS: %s focused Bash groups (%ss)\n' "$TEST_COUNT" "$SECONDS"
