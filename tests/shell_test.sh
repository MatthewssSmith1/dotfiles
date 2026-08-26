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
chmod 0755 "$fake_bin/fzf" "$fake_bin/eza"

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

# Ubuntu deploys the reviewed portable closure, initializes each guarded tool
# offline in order, and sources the host-local layer last exactly once.
home="$TEST_ROOT/home-ubuntu"
mkdir -p "$home/.config/dotfiles/local"
printf ': # host baseline without newline' > "$home/.bashrc"
chmod 0640 "$home/.bashrc"
cp -a "$home/.bashrc" "$TEST_ROOT/ubuntu.original"
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
[[ "$(stat -c %a -- "$home/.bashrc")" == 640 && ! -e "$state" &&
  ! -e "$home/.config/dotfiles/bash/rc.bash" && -f "$home/.config/dotfiles/local/bash.sh" ]] ||
  fail 'Ubuntu Bash removal did not preserve host ownership'
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
set +e
output="$(run_bash_area "$home" ubuntu apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 && ! -e "$home/.local/state/dotfiles/v2/bash.json" ]] || fail 'malformed source block was adopted'
assert_contains "$output" 'partial, malformed'
pass

printf 'PASS: %s focused Bash groups (%ss)\n' "$TEST_COUNT" "$SECONDS"
