#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly COMMON_ROOT="$REPO_DIR/packages/common/bash/.config/dotfiles/bash"
readonly GENERIC_ROOT="$REPO_DIR/packages/generic/bash/.config/dotfiles/bash"
readonly UPSTREAM_ROOT="$REPO_DIR/packages/upstream/bash/.config/dotfiles/upstream/bash"
TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""

cleanup_test() { rm -rf -- "$TEST_ROOT"; }
trap cleanup_test EXIT
fail() { printf 'FAIL: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2; exit 1; }
pass() { ((TEST_COUNT += 1)); }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"; }
assert_same() { cmp -s -- "$1" "$2" || fail "files differ: $1 $2"; }

NETWORK_NAMESPACE=false
if unshare --user --map-current-user --net true >/dev/null 2>&1; then
  NETWORK_NAMESPACE=true
fi

run_network_isolated() {
  if [[ "$NETWORK_NAMESPACE" == true ]]; then
    unshare --user --map-current-user --net -- "$@"
  else
    "$@"
  fi
}

install_network_sentinels() {
  local home="$1" name
  mkdir -p "$home/fake-bin"
  for name in curl wget ssh scp sudo apt apt-get pacman dnf yum apk snap flatpak npm pnpm yarn bun pip pip3; do
    cat > "$home/fake-bin/$name" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s:%s\n' "${0##*/}" "$*" >> "$HOME/network-attempted"
exit 97
SCRIPT
    chmod 0755 "$home/fake-bin/$name"
  done
  cat > "$home/fake-bin/git" <<'SCRIPT'
#!/usr/bin/env bash
case " ${*:-} " in
  *' clone '*|*' fetch '*|*' pull '*|*' push '*|*' ls-remote '*|*' submodule '*)
    printf 'git:%s\n' "$*" >> "$HOME/network-attempted"
    exit 97
    ;;
esac
exec /usr/bin/git "$@"
SCRIPT
  chmod 0755 "$home/fake-bin/git"
}

make_fake_initializer() {
  local path="$1" name="$2" selector="$3"
  cat > "$path" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$*" == "$selector" ]]; then
  printf '%s\n' 'printf "%s\\n" $name-init >> "\$INIT_TRACE"'
fi
SCRIPT
  chmod 0755 "$path"
}

prepare_bash_tools() {
  local home="$1"
  install_network_sentinels "$home"
  for name in eza fzf; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$home/fake-bin/$name"
    chmod 0755 "$home/fake-bin/$name"
  done
  make_fake_initializer "$home/fake-bin/mise" mise 'activate bash'
  make_fake_initializer "$home/fake-bin/starship" starship 'init bash'
  make_fake_initializer "$home/fake-bin/zoxide" zoxide 'init bash'
  make_fake_initializer "$home/fake-bin/wt" worktrunk 'config shell init bash'
}

run_bash_area() {
  local home="$1" profile="$2" operation="$3" fail_at="${4:-}" mode=apply
  [[ "$operation" != remove ]] || mode=remove
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=stage6-matrix-test SELECTED_PROFILE="$profile" MODE="$mode" \
    DOTFILES_TESTING=1 DOTFILES_TEST_FAIL_AT="$fail_at" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/bash.sh"
      AREA_ORDER=(git bash tmux nvim zsh)
      AREA_STATUS=([git]=ready [bash]=framework [tmux]=framework [nvim]=framework [zsh]=framework)
      run_controlled_bash() { :; }
      if [[ "$MODE" == remove ]]; then remove_bash; else preflight_bash; apply_bash; fi
    '
}

run_interactive() {
  local home="$1"
  shift
  HOME="$home" PATH="$home/fake-bin:/usr/bin:/bin" TERM="${TERM:-xterm-256color}" \
    DOTFILES_BASH_TRACE="$home/trace" INIT_TRACE="$home/init-trace" \
    run_network_isolated bash --noprofile -i -c "$*" 2> "$home/stderr"
}

# Bash startup 3: explicit generic selection on WSL warns and omits the adapter.
home="$TEST_ROOT/profile-generic"
mkdir -p "$home"
host="$TEST_ROOT/wsl-host"
mkdir -p "$host/etc" "$host/proc/sys/kernel"
printf 'ID=ubuntu\nVERSION_ID=24.04\n' > "$host/etc/os-release"
printf '6.6.0-microsoft-standard-WSL2\n' > "$host/proc/sys/kernel/osrelease"
TEST_OUTPUT="$(HOME="$home" HOST_ROOT="$host" DOTFILES_TESTING=1 DOTFILES_TEST_UNAME=Linux \
  PROFILE_OVERRIDE=generic MODE=check SCRIPT_NAME=stage6-matrix-test bash -c '
    source "'$REPO_DIR'/lib/common.sh"
    source "'$REPO_DIR'/lib/host.sh"
    detect_host
    select_profile
    printf "profile=%s" "$SELECTED_PROFILE"
  ' 2>&1)"
assert_contains "$TEST_OUTPUT" 'warning: generic profile selected on WSL; WSL adapters are omitted'
assert_contains "$TEST_OUTPUT" 'profile=generic'
pass

# Bash startup 4-5 and 10-14: real startup attachment paths stay once-only and offline.
home="$TEST_ROOT/startup-processes"
mkdir -p "$home/.config/dotfiles/local"
prepare_bash_tools "$home"
printf 'host-local-function() { :; }\n' > "$home/.config/dotfiles/local/bash.sh"
printf 'legacy remainder executed\n' > "$home/.bashrc"
printf 'profile remainder executed\n' > "$home/.profile"
run_bash_area "$home" generic apply
: > "$home/trace"; : > "$home/init-trace"
run_interactive "$home" ':' >/dev/null
[[ "$(grep -c '^generic$' "$home/trace")" == 1 ]] || fail 'interactive startup did not initialize exactly once'
[[ "$(grep -c '^host-local$' "$home/trace")" == 1 ]] || fail 'interactive startup did not reach host-local last'
[[ "$(grep -c '^wsl$' "$home/trace" || true)" == 0 ]] || fail 'explicit generic profile on WSL loaded the WSL adapter'
[[ ! -e "$home/network-attempted" ]] || fail 'ordinary interactive startup invoked a network sentinel'

: > "$home/trace"; : > "$home/init-trace"
HOME="$home" PATH="$home/fake-bin:/usr/bin:/bin" DOTFILES_BASH_TRACE="$home/trace" INIT_TRACE="$home/init-trace" \
  run_network_isolated bash --login -i -c ':' >/dev/null 2> "$home/login-stderr"
[[ "$(grep -c '^generic$' "$home/trace")" == 1 ]] || fail 'login Bash did not reach managed .bashrc exactly once'

: > "$home/trace"; : > "$home/init-trace"
SSH_CONNECTION='192.0.2.1 1 192.0.2.2 2' run_interactive "$home" ':' >/dev/null
[[ "$(grep -c '^generic$' "$home/trace")" == 1 ]] || fail 'SSH-marked interactive Bash did not initialize once'

: > "$home/trace"; : > "$home/init-trace"
HOME="$home" PATH="$home/fake-bin:/usr/bin:/bin" SSH_CONNECTION='192.0.2.1 1 192.0.2.2 2' \
  DOTFILES_BASH_TRACE="$home/trace" run_network_isolated bash --noprofile --norc -c 'source "$HOME/.bashrc"'
[[ ! -s "$home/trace" ]] || fail 'SSH non-interactive Bash initialized managed shell state'

: > "$home/trace"; : > "$home/init-trace"
run_interactive "$home" 'source "$HOME/.bashrc"; source "$HOME/.bashrc"' >/dev/null
[[ "$(grep -c '^generic$' "$home/trace")" == 1 ]] || fail 'same-process .bashrc re-source initialized twice'

: > "$home/trace"; : > "$home/init-trace"
run_interactive "$home" 'bash --noprofile -i -c :' >/dev/null
[[ "$(grep -c '^generic$' "$home/trace")" == 2 ]] || fail 'nested Bash did not initialize once per process'
[[ ! -e "$home/network-attempted" ]] || fail 'login, SSH, or nested startup invoked a network sentinel'
pass

# Bash startup 6-9: login precedence is stable, and created login files are removed safely.
for fixture in profile login posix none; do
  home="$TEST_ROOT/login-$fixture"
  mkdir "$home"
  printf 'rc\n' > "$home/.bashrc"
  case "$fixture" in
    profile)
      printf 'chosen\n' > "$home/.bash_profile"
      printf 'lower\n' > "$home/.bash_login"
      printf 'lowest\n' > "$home/.profile"
      expected=.bash_profile
      ;;
    login)
      printf 'chosen\n' > "$home/.bash_login"
      printf 'lower\n' > "$home/.profile"
      expected=.bash_login
      ;;
    posix)
      printf 'chosen\n' > "$home/.profile"
      expected=.profile
      ;;
    none) expected=.bash_profile ;;
  esac
  [[ "$fixture" == none ]] || cp -a "$home/$expected" "$TEST_ROOT/$fixture.original"
  run_bash_area "$home" generic apply
  jq -e --arg expected "$expected" 'any(.attachments[]; .path == $expected)' \
    "$home/.local/state/dotfiles/v1/bash.json" >/dev/null || fail "wrong login precedence for $fixture"
  run_bash_area "$home" generic remove
  if [[ "$fixture" == none ]]; then
    [[ ! -e "$home/.bash_profile" ]] || fail 'bootstrap-created login file survived removal'
  else
    assert_same "$home/$expected" "$TEST_ROOT/$fixture.original"
  fi
done
for point in bash-after-stow bash-after-attachments bash-after-validation; do
  home="$TEST_ROOT/bash-native-fault-$point"
  mkdir "$home"
  printf 'native original without newline' > "$home/.bashrc"
  chmod 0640 "$home/.bashrc"
  cp -a "$home" "$TEST_ROOT/native-$point.original"
  if run_bash_area "$home" omarchy apply "$point" > "$home.log" 2>&1; then
    fail "native Bash apply fault succeeded: $point"
  fi
  diff --no-dereference -r "$home" "$TEST_ROOT/native-$point.original" >/dev/null || \
    fail "native Bash apply rollback was incomplete: $point"
done
for point in bash-remove-after-attachments bash-remove-after-links; do
  home="$TEST_ROOT/bash-native-remove-fault-$point"
  mkdir "$home"
  printf 'native original\n' > "$home/.bashrc"
  run_bash_area "$home" omarchy apply
  cp -a "$home" "$TEST_ROOT/native-$point.original"
  if run_bash_area "$home" omarchy remove "$point" > "$home.log" 2>&1; then
    fail "native Bash remove fault succeeded: $point"
  fi
  diff --no-dereference -r "$home" "$TEST_ROOT/native-$point.original" >/dev/null || \
    fail "native Bash remove rollback was incomplete: $point"
done
pass

# Bash startup 14-21: initializer guards, editor semantics, aliases, functions, and Readline are real.
home="$TEST_ROOT/startup-details"
mkdir -p "$home/.config/dotfiles/local"
prepare_bash_tools "$home"
cat > "$home/.config/dotfiles/local/bash.sh" <<'SCRIPT'
host_alias_target() { :; }
alias host_last=host_alias_target
SCRIPT
run_bash_area "$home" generic apply
: > "$home/trace"; : > "$home/init-trace"
TEST_OUTPUT="$(TERM=dumb EDITOR=existing VISUAL= run_interactive "$home" \
  'alias ls; alias ff; alias host_last; declare -F tdl tdlm tsl host_alias_target; printf "|%s|<%s>" "$EDITOR" "$VISUAL"')"
assert_contains "$TEST_OUTPUT" "alias ls='eza -lh --group-directories-first --icons=auto'"
assert_contains "$TEST_OUTPUT" "alias ff="
assert_contains "$TEST_OUTPUT" '|existing|<>'
[[ "$(< "$home/init-trace")" != *starship-init* ]] || fail 'TERM=dumb initialized Starship'
[[ "$(< "$home/init-trace")" == *mise-init* && "$(< "$home/init-trace")" == *zoxide-init* && \
  "$(< "$home/init-trace")" == *worktrunk-init* ]] || fail 'expected guarded initializers did not run'
[[ ! -e "$home/.inputrc" ]] || fail 'managed startup created ~/.inputrc'
HOME="$home" PATH=/usr/bin:/bin DOTFILES_BASH_TRACE="$home/missing-trace" \
  run_network_isolated bash --noprofile -i -c ':' > "$home/missing-output" 2> "$home/missing-errors"
[[ ! -s "$home/missing-output" ]] || fail 'missing-tool startup emitted stdout'
case "$(< "$home/missing-errors")" in
  ''|bash:\ cannot\ set\ terminal\ process\ group* ) ;;
  *) fail 'missing optional tools emitted startup diagnostics' ;;
esac
[[ ! -e "$home/network-attempted" ]] || fail 'detailed or missing-tool startup invoked a network sentinel'
pass

# Attachment 8, 10-13: outside edits survive; generic bypasses while native executes and refreshes.
home="$TEST_ROOT/attachment-edits"
mkdir "$home"
printf 'printf legacy > "$HOME/legacy-ran"\n' > "$home/.bashrc"
run_bash_area "$home" generic apply
printf '# outside edit\n' >> "$home/.bashrc"
HOME="$home" PATH=/usr/bin:/bin bash --noprofile -i -c ':' >/dev/null 2>/dev/null
[[ ! -e "$home/legacy-ran" ]] || fail 'generic prepend did not bypass legacy remainder'
run_bash_area "$home" generic remove
[[ "$(< "$home/.bashrc")" == $'printf legacy > "$HOME/legacy-ran"\n# outside edit' ]] || \
  fail 'outside attachment edit did not survive removal'

home="$TEST_ROOT/native-exec"
mkdir "$home"
printf 'printf native-baseline >> "$HOME/native-trace"\n' > "$home/.bashrc"
run_bash_area "$home" omarchy apply
HOME="$home" PATH=/usr/bin:/bin bash --noprofile -i -c ':' >/dev/null 2>/dev/null
[[ "$(< "$home/native-trace")" == native-baseline ]] || fail 'native append did not execute native baseline'
printf 'printf refreshed >> "$HOME/native-trace"\n' > "$home/.bashrc"
run_bash_area "$home" omarchy apply
printf '# >>> dotfiles managed bash common >>>\npartial\n' > "$home/.bashrc"
if run_bash_area "$home" omarchy apply > "$home/drift-output" 2>&1; then
  fail 'native partial refresh drift was accepted'
fi
assert_contains "$(< "$home/drift-output")" 'partial, malformed, nested, duplicate, or modified'
pass

# Attachment 14: each pre-commit Bash fault restores links, files, modes, and state.
for point in bash-after-stow bash-after-attachments bash-after-validation; do
  home="$TEST_ROOT/bash-fault-$point"
  mkdir "$home"
  printf 'original without newline' > "$home/.bashrc"
  chmod 0640 "$home/.bashrc"
  cp -a "$home" "$TEST_ROOT/$point.original"
  if run_bash_area "$home" generic apply "$point" > "$home.log" 2>&1; then
    fail "Bash apply fault succeeded: $point"
  fi
  diff --no-dereference -r "$home" "$TEST_ROOT/$point.original" >/dev/null || \
    fail "Bash apply rollback was incomplete: $point"
done
for point in bash-remove-after-login bash-remove-after-attachments bash-remove-after-links; do
  home="$TEST_ROOT/bash-remove-fault-$point"
  mkdir "$home"
  printf 'original\n' > "$home/.bashrc"
  run_bash_area "$home" generic apply
  cp -a "$home" "$TEST_ROOT/$point.original"
  if run_bash_area "$home" generic remove "$point" > "$home.log" 2>&1; then
    fail "Bash remove fault succeeded: $point"
  fi
  diff --no-dereference -r "$home" "$TEST_ROOT/$point.original" >/dev/null || \
    fail "Bash remove rollback was incomplete: $point"
done
pass

# Ownership 3, 5-7, 10: exported functions and executable candidates are rejected without execution.
owner_home="$TEST_ROOT/ownership"
mkdir -p "$owner_home" "$TEST_ROOT/owner-bin" "$TEST_ROOT/project-bin" "$TEST_ROOT/extra-bin"
for bin in owner-bin project-bin extra-bin; do
  printf '#!/usr/bin/env bash\nprintf invoked >> %q\n' "$TEST_ROOT/rejected-executed" > "$TEST_ROOT/$bin/fzf"
  chmod 0755 "$TEST_ROOT/$bin/fzf"
done
cat > "$TEST_ROOT/dpkg-query" <<'SCRIPT'
#!/usr/bin/env bash
case "$2" in */owner-bin/fzf|/usr/bin/fzf|/bin/fzf) ;; *) exit 1 ;; esac
printf 'fzf: %s\n' "$2"
SCRIPT
chmod 0755 "$TEST_ROOT/dpkg-query"
run_owner_check() {
  HOME="$owner_home" TARGET_ROOT="$owner_home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-matrix-test \
    DOTFILES_TESTING=1 DOTFILES_TEST_BASH_DISTRO_BIN="$TEST_ROOT/owner-bin" \
    DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/dpkg-query" PATH="$1:/usr/bin:/bin" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/bash.sh"
      [[ "${EXPORT_SHADOW:-}" != 1 ]] || { fzf() { printf invoked >> "'$TEST_ROOT'/rejected-executed"; }; export -f fzf; }
      bash_validate_distro_command fzf fzf
    '
}
run_owner_check "$TEST_ROOT/owner-bin" || fail 'approved sole distro candidate was rejected'
if EXPORT_SHADOW=1 run_owner_check "$TEST_ROOT/owner-bin" > "$TEST_ROOT/exported.out" 2>&1; then
  fail 'exported function shadow was accepted'
fi
assert_contains "$(< "$TEST_ROOT/exported.out")" 'shadowed by a shell function'
for candidate in project-bin extra-bin; do
  if run_owner_check "$TEST_ROOT/owner-bin:$TEST_ROOT/$candidate" > "$TEST_ROOT/$candidate.out" 2>&1; then
    fail "$candidate shadow was accepted"
  fi
  assert_contains "$(< "$TEST_ROOT/$candidate.out")" "unapproved PATH candidate: $TEST_ROOT/$candidate/fzf"
done
mkdir -p "$owner_home/.local/bin" "$TEST_ROOT/project/.bin"
cp "$TEST_ROOT/project-bin/fzf" "$owner_home/.local/bin/fzf"
cp "$TEST_ROOT/project-bin/fzf" "$TEST_ROOT/project/.bin/fzf"
chmod 0755 "$owner_home/.local/bin/fzf" "$TEST_ROOT/project/.bin/fzf"
for shadow in "$owner_home/.local/bin" "$TEST_ROOT/project/.bin"; do
  if run_owner_check "$shadow:$TEST_ROOT/owner-bin" > "$TEST_ROOT/first-shadow.out" 2>&1; then
    fail "higher-precedence executable shadow was accepted: $shadow"
  fi
  assert_contains "$(< "$TEST_ROOT/first-shadow.out")" "unapproved PATH candidate: $shadow/fzf"
done
[[ ! -e "$TEST_ROOT/rejected-executed" ]] || fail 'ownership validation executed a rejected object'
pass

# Ownership 6 and 9: project mise resolution is rejected; absent optional tools remain startup-safe.
mise_home="$TEST_ROOT/mise-owner"
expected_wt="$mise_home/.local/share/dotfiles/provisioning/tools/worktrunk/0.1.0/wt"
project_wt="$TEST_ROOT/project-wt/wt"
mkdir -p "$(dirname -- "$expected_wt")" "$(dirname -- "$project_wt")" "$mise_home/.local/share/mise/shims"
printf '#!/usr/bin/env bash\nexit 0\n' > "$expected_wt"
printf '#!/usr/bin/env bash\nprintf invoked > %q\n' "$TEST_ROOT/project-wt-invoked" > "$project_wt"
chmod 0755 "$expected_wt" "$project_wt"
cat > "$TEST_ROOT/mise-which" <<SCRIPT
#!/usr/bin/env bash
[[ "\$1" == which && "\$2" == wt ]] || exit 1
printf '%s\n' '$expected_wt'
SCRIPT
chmod 0755 "$TEST_ROOT/mise-which"
cat > "$TEST_ROOT/worktrunk-manifest.json" <<JSON
{"tools":[{"id":"worktrunk","install_root":".local/share/dotfiles/provisioning/tools/worktrunk/0.1.0","artifact":{"executable":"wt"}}]}
JSON
TEST_OUTPUT="$(HOME="$mise_home" TARGET_ROOT="$mise_home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-matrix-test \
  PATH="$TEST_ROOT/project-wt:$mise_home/.local/share/mise/shims:/usr/bin:/bin" \
  MISE_BIN="$TEST_ROOT/mise-which" PROVISIONING_MANIFEST="$TEST_ROOT/worktrunk-manifest.json" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/bash.sh"
    PROVISIONING_MANIFEST="'$TEST_ROOT'/worktrunk-manifest.json"
    MISE_BIN="'$TEST_ROOT'/mise-which"
    provision_tool_status() { :; }
    bash_validate_optional_mise_command worktrunk wt
  ' 2>&1 || true)"
assert_contains "$TEST_OUTPUT" "optional mise command 'wt' has an unapproved PATH candidate: $project_wt"
[[ ! -e "$TEST_ROOT/project-wt-invoked" ]] || fail 'project-local mise shadow was executed'
pass

# Denied-network check runs checkout startup twice and remains non-mutating.
home="$TEST_ROOT/network-check"
mkdir "$home"
prepare_bash_tools "$home"
run_network_isolated env HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
  SCRIPT_NAME=stage6-matrix-test SELECTED_PROFILE=generic MODE=check DOTFILES_TESTING=1 \
  PATH="$home/fake-bin:/usr/bin:/bin" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/bash.sh"
    AREA_ORDER=(git bash tmux nvim zsh)
    AREA_STATUS=([git]=ready [bash]=framework [tmux]=framework [nvim]=framework [zsh]=framework)
    run_controlled_bash() {
      HOME="$HOME" PATH="$HOME/fake-bin:/usr/bin:/bin" DOTFILES_BASH_CONTROLLED_VALIDATION=1 \
        DOTFILES_BASH_VALIDATE_OWNERSHIP=0 DOTFILES_BASH_VALIDATION_ROOT="'$COMMON_ROOT'" \
        DOTFILES_BASH_VALIDATION_GENERIC="'$GENERIC_ROOT'" DOTFILES_BASH_VALIDATION_WSL= \
        DOTFILES_BASH_VALIDATION_UPSTREAM="'$UPSTREAM_ROOT'" \
        bash --noprofile --norc -i -c "source \"\$DOTFILES_BASH_VALIDATION_ROOT/rc.bash\"" >/dev/null 2>"$HOME/check-errors"
    }
    preflight_bash
  '
[[ ! -e "$home/network-attempted" ]] || fail 'Bash check invoked a network sentinel'
[[ -z "$(find "$home" -mindepth 1 ! -path "$home/fake-bin*" ! -name check-errors -print -quit)" ]] || \
  fail 'Bash check mutated fixture HOME'
pass

# Denied-network remove is sentinel-backed and does not require namespace support.
home="$TEST_ROOT/network-remove"
mkdir "$home"
install_network_sentinels "$home"
run_bash_area "$home" generic apply
PATH="$home/fake-bin:/usr/bin:/bin" run_network_isolated env HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" \
  DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-matrix-test SELECTED_PROFILE=generic MODE=remove bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/bash.sh"
    AREA_ORDER=(git bash tmux nvim zsh)
    AREA_STATUS=([git]=ready [bash]=framework [tmux]=framework [nvim]=framework [zsh]=framework)
    remove_bash
  '
[[ ! -e "$home/network-attempted" ]] || fail 'Bash removal invoked a network sentinel'
pass

printf 'PASS: %d exhaustive Stage 6 matrix test groups (network namespace: %s)\n' "$TEST_COUNT" "$NETWORK_NAMESPACE"
