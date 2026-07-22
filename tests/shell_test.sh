#!/usr/bin/env bash
# Shell domain: Bash payload/startup/matrix/ownership, zsh migration lifecycle, and ready-area gating.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly COMMON_ROOT="$REPO_DIR/packages/common/bash/.config/dotfiles/bash"
readonly GENERIC_ROOT="$REPO_DIR/packages/generic/bash/.config/dotfiles/bash"
readonly WSL_ROOT="$REPO_DIR/packages/wsl/bash/.config/dotfiles/bash"
readonly UPSTREAM_ROOT="$REPO_DIR/packages/upstream/bash/.config/dotfiles/upstream/bash"

run_payload() {
  local home="$1" profile="$2" validation="$3" command="$4"
  local wsl_root=""
  [[ "$profile" != wsl ]] || wsl_root="$WSL_ROOT"
  HOME="$home" PATH="$home/fake-bin:/usr/bin:/bin" TERM=xterm-256color \
    DOTFILES_BASH_CONTROLLED_VALIDATION=1 DOTFILES_BASH_VALIDATE_OWNERSHIP="$validation" \
    DOTFILES_BASH_VALIDATION_ROOT="$COMMON_ROOT" DOTFILES_BASH_VALIDATION_GENERIC="$GENERIC_ROOT" \
    DOTFILES_BASH_VALIDATION_WSL="$wsl_root" DOTFILES_BASH_VALIDATION_UPSTREAM="$UPSTREAM_ROOT" \
    DOTFILES_BASH_TRACE="$home/trace" INIT_TRACE="$home/init-trace" \
    bash --noprofile --norc -i -c "$command" 2> "$home/stderr"
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

# ---------------------------------------------------------------------------
# Bash payload and startup sections (from stage6_shell_test.sh)
# ---------------------------------------------------------------------------

# Package inventory and executable modes are explicit and contain no host-local payload.
for file in \
  "$COMMON_ROOT/rc.bash" "$COMMON_ROOT/integrations.bash" "$COMMON_ROOT/personal.bash" \
  "$GENERIC_ROOT/generic.bash" "$GENERIC_ROOT/env.bash" "$GENERIC_ROOT/init.bash" \
  "$WSL_ROOT/wsl.bash"; do
  [[ -f "$file" && ! -L "$file" && "$(stat -c %a -- "$file")" == 644 ]] || fail "invalid managed Bash payload: $file"
done
for wrapper in bat fd; do
  [[ -x "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/$wrapper" && \
    "$(stat -c %a -- "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/$wrapper")" == 755 ]] || \
    fail "$wrapper wrapper mode is not 0755"
done
[[ ! -e "$REPO_DIR/packages/common/bash/.config/dotfiles/local/bash.sh" ]] || fail 'package contains a host-local Bash file'
grep -qxF '[settings]' "$REPO_DIR/packages/common/bash/.config/mise/conf.d/20-dotfiles-common.toml" || \
  fail 'managed mise settings are not in the settings table'
pass

# WSL startup loads each layer once, preserves explicit empty editors, and exposes local functions last.
home="$TEST_ROOT/home-startup"
mkdir -p "$home/fake-bin" "$home/.config/dotfiles/local"
for command_name in eza fzf; do printf '#!/usr/bin/env bash\nexit 0\n' > "$home/fake-bin/$command_name"; chmod 0755 "$home/fake-bin/$command_name"; done
for command_name in curl wget git ssh sudo apt apt-get; do
  printf '#!/usr/bin/env bash\nprintf attempted >> %q\nexit 99\n' "$home/network-attempted" > "$home/fake-bin/$command_name"
  chmod 0755 "$home/fake-bin/$command_name"
done
make_fake_initializer "$home/fake-bin/mise" mise 'activate bash'
make_fake_initializer "$home/fake-bin/starship" starship 'init bash'
make_fake_initializer "$home/fake-bin/zoxide" zoxide 'init bash'
cat > "$home/fake-bin/wt" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" == 'config shell init bash' ]]; then
  while IFS=: read -r key value; do
    case "$key" in
      CapEff|NoNewPrivs) printf '%s:%s\n' "$key" "${value//[[:space:]]/}" >> "$HOME/wt-privileges" ;;
    esac
  done < /proc/self/status
  readlink /proc/self/ns/net > "$HOME/wt-netns"
  if exec 9<>/dev/tcp/127.0.0.1/9; then printf escaped > "$HOME/wt-network-escaped"; fi
  printf '%s\n' 'printf "%s\n" worktrunk-init >> "$INIT_TRACE"'
fi
SCRIPT
chmod 0755 "$home/fake-bin/wt"
cat > "$home/.config/dotfiles/local/bash.sh" <<'SCRIPT'
host_local_function() { :; }
SCRIPT
: > "$home/trace"
: > "$home/init-trace"
TEST_OUTPUT="$(EDITOR= VISUAL= run_payload "$home" wsl 0 \
  'bind() { printf "bind:%s\n" "$2" >> "$INIT_TRACE"; }; source "$DOTFILES_BASH_VALIDATION_ROOT/rc.bash"; source "$DOTFILES_BASH_VALIDATION_ROOT/rc.bash"; alias ls >/dev/null; declare -F tdl host_local_function >/dev/null; printf "editor=<%s> visual=<%s> guard=%s" "$EDITOR" "$VISUAL" "$(export -p | grep -c __DOTFILES_BASH_RC_PID || true)"')"
[[ "$TEST_OUTPUT" == 'editor=<> visual=<> guard=0' ]] || fail 'startup did not preserve empty editor values or unexported guard'
expected_trace='generic
environment
upstream-shell
upstream-aliases
upstream-tmux
mise
starship
zoxide
fzf
inputrc
wsl
worktrunk
personal
host-local'
[[ "$(< "$home/trace")" == "$expected_trace" ]] || fail 'managed WSL source order or exactly-once behavior is wrong'
mapfile -t init_trace < "$home/init-trace"
[[ "${init_trace[0]}" == mise-init && "${init_trace[1]}" == starship-init && \
  "${init_trace[2]}" == zoxide-init && \
  "${init_trace[${#init_trace[@]}-2]}" == "bind:$UPSTREAM_ROOT/inputrc" && \
  "${init_trace[${#init_trace[@]}-1]}" == worktrunk-init ]] || fail 'initializer order is wrong'
[[ ! -e "$home/network-attempted" ]] || fail 'ordinary managed Bash startup attempted a network-capable command'
[[ "$(< "$home/wt-privileges")" == $'CapEff:0000000000000000\nNoNewPrivs:1' ]] || \
  fail 'Bash Worktrunk initializer retained capabilities or lacked no-new-privileges'
[[ "$(< "$home/wt-netns")" != "$(readlink /proc/self/ns/net)" && ! -e "$home/wt-network-escaped" ]] || \
  fail 'Bash Worktrunk initializer did not run in its denied-network namespace'
[[ "$(< "$home/stderr")" == bash:*'cannot set terminal process group'* ]] || fail 'managed startup emitted unexpected diagnostics'

managed_definitions="$(run_payload "$home" generic 0 \
  'source "$DOTFILES_BASH_VALIDATION_ROOT/rc.bash"; alias -p; declare -f sff zd open n tdl tdlm tsl')"
expected_definitions="$(HOME="$home" PATH="$home/fake-bin:/usr/bin:/bin" TERM=xterm-256color \
  bash --noprofile --norc -c 'shopt -s expand_aliases; source "$1"; source "$2"; alias -p; declare -f sff zd open n tdl tdlm tsl' \
  _ "$UPSTREAM_ROOT/aliases" "$UPSTREAM_ROOT/fns/tmux")"
[[ "$managed_definitions" == "$expected_definitions" ]] || fail 'managed aliases or tmux helpers differ from the pinned payload behavior'
pass

# Non-interactive sourcing returns before mutation; TERM=dumb and missing tools remain silent.
home="$TEST_ROOT/home-guards"
mkdir -p "$home/fake-bin"
: > "$home/trace"
TEST_OUTPUT="$(HOME="$home" PATH=/usr/bin:/bin DOTFILES_BASH_TRACE="$home/trace" \
  env -u EDITOR -u VISUAL bash --noprofile --norc -c "source '$COMMON_ROOT/rc.bash'; printf '%s' \"\${EDITOR-unset}\"")"
[[ "$TEST_OUTPUT" == unset && ! -s "$home/trace" ]] || fail 'non-interactive dispatcher mutated shell state'
TEST_OUTPUT="$(unset EDITOR VISUAL; TERM=dumb run_payload "$home" generic 1 \
  'source "$DOTFILES_BASH_VALIDATION_ROOT/rc.bash"; printf "%s:%s" "$EDITOR" "$VISUAL"')"
[[ "$TEST_OUTPUT" == nvim:nvim ]] || fail 'unset editor defaults were not applied'
[[ ! -s "$home/stderr" || "$(< "$home/stderr")" == bash:*'cannot set terminal process group'* ]] || \
  fail 'missing optional tools emitted managed diagnostics'
pass

# pnpm global-bin directories are exported once, bin first, on generic rebuilds and native startups.
home="$TEST_ROOT/home-pnpm"
mkdir -p "$home/fake-bin"
pnpm_probe='source "$DOTFILES_BASH_VALIDATION_ROOT/rc.bash"; declare -p PNPM_HOME; printf "%s" "$PATH"'
run_pnpm_payload() {
  local generic_root="$1" inherited_path="$2"
  HOME="$home" PATH="$inherited_path" TERM=xterm-256color \
    DOTFILES_BASH_CONTROLLED_VALIDATION=1 DOTFILES_BASH_VALIDATE_OWNERSHIP=1 \
    DOTFILES_BASH_VALIDATION_ROOT="$COMMON_ROOT" DOTFILES_BASH_VALIDATION_GENERIC="$generic_root" \
    DOTFILES_BASH_VALIDATION_WSL="" DOTFILES_BASH_VALIDATION_UPSTREAM="$UPSTREAM_ROOT" \
    DOTFILES_BASH_TRACE="$home/trace" bash --noprofile --norc -i -c "$pnpm_probe" 2>/dev/null
}
TEST_OUTPUT="$(run_pnpm_payload "$GENERIC_ROOT" "$home/fake-bin:/usr/bin:/bin")"
[[ "$TEST_OUTPUT" == "declare -x PNPM_HOME=\"$home/.local/share/pnpm\""$'\n'"$home/.local/share/pnpm/bin:$home/.local/share/pnpm:"* ]] || \
  fail 'pnpm directories are not exported at the front of the rebuilt generic PATH'
TEST_OUTPUT="$(run_pnpm_payload "$GENERIC_ROOT" \
  "$home/.local/share/pnpm/bin:$home/.local/share/pnpm:$home/fake-bin:/usr/bin:/bin")"
[[ "$(tr ':' '\n' <<< "${TEST_OUTPUT#*$'\n'}" | grep -cxF "$home/.local/share/pnpm")" == 1 && \
  "$(tr ':' '\n' <<< "${TEST_OUTPUT#*$'\n'}" | grep -cxF "$home/.local/share/pnpm/bin")" == 1 ]] || \
  fail 'inherited pnpm PATH entries were duplicated'
mkdir -p "$TEST_ROOT/pnpm-empty-generic"
TEST_OUTPUT="$(run_pnpm_payload "$TEST_ROOT/pnpm-empty-generic" "$home/fake-bin:/usr/bin:/bin")"
[[ "$TEST_OUTPUT" == *$'\n'"$home/.local/share/pnpm/bin:$home/.local/share/pnpm:$home/fake-bin:"* ]] || \
  fail 'native startup without the generic layer did not prepend pnpm directories'
pass

# Private wrappers select distro command-name variants, preserve arguments/status, and never recurse.
distro_bin="$TEST_ROOT/distro-bin"
mkdir "$distro_bin"
cat > "$distro_bin/batcat" <<'SCRIPT'
#!/usr/bin/env bash
printf 'batcat:%s\n' "$*"
exit 23
SCRIPT
cat > "$distro_bin/fdfind" <<'SCRIPT'
#!/usr/bin/env bash
printf 'fdfind:%s\n' "$*"
exit 24
SCRIPT
chmod 0755 "$distro_bin/batcat" "$distro_bin/fdfind"
set +e
TEST_OUTPUT="$(DOTFILES_TESTING=1 DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" \
  "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/bat" --style plain 'a b')"
status=$?
set -e
[[ "$status" == 23 && "$TEST_OUTPUT" == 'batcat:--style plain a b' ]] || fail 'bat wrapper did not preserve fallback arguments/status'
set +e
TEST_OUTPUT="$(DOTFILES_TESTING=1 DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" \
  "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/fd" --hidden needle)"
status=$?
set -e
[[ "$status" == 24 && "$TEST_OUTPUT" == 'fdfind:--hidden needle' ]] || fail 'fd wrapper did not preserve fallback arguments/status'
cat > "$distro_bin/bat" <<'SCRIPT'
#!/usr/bin/env bash
printf 'bat:%s\n' "$*"
exit 25
SCRIPT
cat > "$distro_bin/fd" <<'SCRIPT'
#!/usr/bin/env bash
printf 'fd:%s\n' "$*"
exit 26
SCRIPT
chmod 0755 "$distro_bin/bat" "$distro_bin/fd"
set +e
TEST_OUTPUT="$(DOTFILES_TESTING=1 DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" \
  "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/bat" preferred)"
status=$?
set -e
[[ "$status" == 25 && "$TEST_OUTPUT" == 'bat:preferred' ]] || fail 'bat wrapper did not prefer the canonical distro command'
set +e
TEST_OUTPUT="$(DOTFILES_TESTING=1 DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" \
  "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/fd" preferred)"
status=$?
set -e
[[ "$status" == 26 && "$TEST_OUTPUT" == 'fd:preferred' ]] || fail 'fd wrapper did not prefer the canonical distro command'
pass

# The production controlled interactive shell validates checkout wrappers and sees host-local non-exported shadows.
controlled_home="$TEST_ROOT/home-controlled"
controlled_bin="$TEST_ROOT/controlled-bin"
mkdir -p "$controlled_home/.local/bin" "$controlled_home/.local/state/dotfiles/provisioning/v1" \
  "$controlled_home/.local/share/dotfiles/provisioning/tools/starship/1.26.0" \
  "$controlled_home/.local/share/mise/installs/aqua-starship-starship" "$controlled_bin"
cat > "$controlled_home/.local/bin/mise" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf '2026.7.7 linux-x64\n' ;;
  activate) exit 0 ;;
  *) exit 1 ;;
esac
SCRIPT
cat > "$controlled_home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship" <<'SCRIPT'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && printf 'starship 1.26.0\n'
SCRIPT
chmod 0755 "$controlled_home/.local/bin/mise" \
  "$controlled_home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship"
ln -s "$controlled_home/.local/share/dotfiles/provisioning/tools/starship/1.26.0" \
  "$controlled_home/.local/share/mise/installs/aqua-starship-starship/1.26.0"
launcher_content="#!/usr/bin/env bash
exec $controlled_home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship \"\$@\""
printf '%s\n' "$launcher_content" > "$controlled_home/.local/bin/starship"
chmod 0755 "$controlled_home/.local/bin/starship"
tool_hash="$(sha256sum "$controlled_home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship")"
tool_hash="${tool_hash%% *}"
launcher_hash="$(printf '%s\n' "$launcher_content" | sha256sum)"
launcher_hash="${launcher_hash%% *}"
jq -cn --arg manifest "$(sha256sum "$REPO_DIR/manifests/provisioning.json" | cut -d' ' -f1)" \
  --arg tool_hash "$tool_hash" --arg launcher_hash "$launcher_hash" '
  {schema_version:1,manifest_sha256:$manifest,
   tools:[{id:"starship",backend:"aqua:starship/starship",version:"1.26.0",platform:"linux-x86_64",
     install_root:".local/share/dotfiles/provisioning/tools/starship/1.26.0",executable:"starship",executable_sha256:$tool_hash}],
   launchers:[{tool_id:"starship",destination:".local/bin/starship",content_sha256:$launcher_hash}]}' \
  > "$controlled_home/.local/state/dotfiles/provisioning/v1/receipt.json"
chmod 0600 "$controlled_home/.local/state/dotfiles/provisioning/v1/receipt.json"
for command_name in fzf zoxide eza rg batcat fdfind; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$controlled_bin/$command_name"
  chmod 0755 "$controlled_bin/$command_name"
done
cat > "$TEST_ROOT/controlled-dpkg-query" <<SCRIPT
#!/usr/bin/env bash
case "\$2" in
  */fzf) package=fzf ;; */zoxide) package=zoxide ;; */eza) package=eza ;; */rg) package=ripgrep ;;
  */batcat) package=bat ;; */fdfind) package=fd-find ;; *) exit 1 ;;
esac
printf '%s: %s\n' "\$package" "\$2"
SCRIPT
chmod 0755 "$TEST_ROOT/controlled-dpkg-query"
run_production_controlled() {
  HOME="$controlled_home" TARGET_ROOT="$controlled_home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=stage6-shell-test SELECTED_PROFILE=generic MODE=check DOTFILES_TESTING=1 \
    DOTFILES_TEST_BASH_DISTRO_BIN="$controlled_bin" DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/controlled-dpkg-query" \
    PATH="$controlled_home/.local/bin:$controlled_bin:/usr/bin:/bin" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/bash.sh"
      PROVISIONING_MANIFEST="$DOTFILES_DIR/manifests/provisioning.json"
      PROVISIONING_RECEIPT="$HOME/.local/state/dotfiles/provisioning/v1/receipt.json"
      PROVISIONING_MANIFEST_SHA="$(sha256_file "$PROVISIONING_MANIFEST")"
      PROVISIONING_PLATFORM=linux-x86_64
      run_controlled_bash checkout true
      run_sandboxed_bash_local_validation
    '
}
run_production_controlled || fail 'production controlled interactive ownership validation rejected approved fixture owners'
mkdir -p "$controlled_home/.config/dotfiles/local"
cat > "$controlled_home/.config/dotfiles/local/bash.sh" <<'SCRIPT'
: > "$HOME/sandbox-side-effect"
host_local_safe_function() { :; }
SCRIPT
run_production_controlled || fail 'sandboxed host-local validation rejected safe fixture behavior'
[[ ! -e "$controlled_home/sandbox-side-effect" ]] || fail 'host-local validation wrote through to the real fixture HOME'
remount_trace="$TEST_ROOT/remount-trace"
cat > "$controlled_home/.config/dotfiles/local/bash.sh" <<'SCRIPT'
printf 'attempted\n' > "${DOTFILES_TEST_REMOUNT_TRACE:?}"
while IFS=: read -r key value; do
  case "$key" in
    CapEff|NoNewPrivs) printf '%s:%s\n' "$key" "${value//[[:space:]]/}" >> "$DOTFILES_TEST_REMOUNT_TRACE" ;;
  esac
done < /proc/self/status
if /usr/bin/mount -o remount,bind,rw "$REAL_HOME" >/dev/null 2>&1; then
  printf escaped >> "$DOTFILES_TEST_REMOUNT_TRACE"
  printf escaped > "$REAL_HOME/remount-escaped"
else
  printf denied >> "$DOTFILES_TEST_REMOUNT_TRACE"
fi
SCRIPT
export DOTFILES_TEST_REMOUNT_TRACE="$remount_trace"
run_production_controlled || fail 'capability-free host-local remount fixture failed validation'
unset DOTFILES_TEST_REMOUNT_TRACE
[[ "$(< "$remount_trace")" == $'attempted\nCapEff:0000000000000000\nNoNewPrivs:1\ndenied' && \
  ! -e "$controlled_home/remount-escaped" ]] || \
  fail 'host-local validation remounted or changed the real fixture HOME'
cat > "$controlled_home/.config/dotfiles/local/bash.sh" <<SCRIPT
fzf() { printf invoked > "$TEST_ROOT/controlled-shadow-invoked"; }
SCRIPT
set +e
TEST_OUTPUT="$(run_production_controlled 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'controlled shell accepted a non-exported host-local function shadow'
assert_contains "$TEST_OUTPUT" "managed Bash command 'fzf' is shadowed by a shell function"
[[ ! -e "$TEST_ROOT/controlled-shadow-invoked" ]] || fail 'controlled shell executed a rejected non-exported function'
cat > "$controlled_home/.config/dotfiles/local/bash.sh" <<'SCRIPT'
curl https://example.invalid/
SCRIPT
set +e
TEST_OUTPUT="$(run_production_controlled 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'sandboxed host-local validation accepted a network-command attempt'
assert_contains "$TEST_OUTPUT" 'host-local Bash validation attempted a network-capable command'
rm "$controlled_home/.config/dotfiles/local/bash.sh"
pass

run_area_fixture() {
  local home="$1" profile="$2" operation="$3"
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=stage6-shell-test SELECTED_PROFILE="$profile" MODE="$([[ "$operation" == remove ]] && printf remove || printf apply)" \
    bash -c '
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

# Generic lifecycle preserves bytes/modes, chooses login precedence once, and removes exact blocks and links.
home="$TEST_ROOT/home-lifecycle"
mkdir -p "$home/.config/opencode"
printf 'untouched OpenCode fixture\n' > "$home/.config/opencode/opencode.json"
opencode_hash="$(sha256sum "$home/.config/opencode/opencode.json")"
printf 'legacy rc without newline' > "$home/.bashrc"
printf 'profile legacy\n' > "$home/.profile"
chmod 0640 "$home/.bashrc" "$home/.profile"
cp -a "$home/.bashrc" "$TEST_ROOT/rc.original"
cp -a "$home/.profile" "$TEST_ROOT/profile.original"
run_area_fixture "$home" generic apply
state="$home/.local/state/dotfiles/v1/bash.json"
jq -e '.profile == "generic" and (.attachments | length) == 2 and any(.attachments[]; .path == ".profile")' "$state" >/dev/null || \
  fail 'generic Bash state did not retain selected login path'
printf 'later higher precedence\n' > "$home/.bash_profile"
run_area_fixture "$home" generic apply
jq -e 'any(.attachments[]; .path == ".profile") and (all(.attachments[]; .path != ".bash_profile"))' "$state" >/dev/null || \
  fail 'reapply silently moved the stable login attachment'
state_hash="$(sha256sum "$state")"
rc_hash="$(sha256sum "$home/.bashrc")"
profile_hash="$(sha256sum "$home/.profile")"
set +e
TEST_OUTPUT="$(HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
  SCRIPT_NAME=stage6-shell-test MODE=remove DOTFILES_TESTING=1 DOTFILES_TEST_FAIL_AT=bash-remove-after-attachments \
  bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/bash.sh"
    AREA_ORDER=(git bash tmux nvim zsh)
    AREA_STATUS=([git]=ready [bash]=framework [tmux]=framework [nvim]=framework [zsh]=framework)
    remove_bash
  ' 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'injected Bash removal fault succeeded'
assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'bash'"
[[ "$(sha256sum "$state")" == "$state_hash" && "$(sha256sum "$home/.bashrc")" == "$rc_hash" && \
  "$(sha256sum "$home/.profile")" == "$profile_hash" ]] || fail 'removal fault did not restore state or attachments'
run_area_fixture "$home" generic remove
assert_same "$home/.bashrc" "$TEST_ROOT/rc.original"
assert_same "$home/.profile" "$TEST_ROOT/profile.original"
[[ "$(stat -c %a -- "$home/.bashrc")" == 640 && "$(stat -c %a -- "$home/.profile")" == 640 ]] || \
  fail 'removal did not preserve startup modes'
[[ "$(< "$home/.bash_profile")" == 'later higher precedence' ]] || fail 'removal touched unrelated later login file'
[[ ! -e "$state" && ! -e "$home/.config/dotfiles/bash/rc.bash" ]] || fail 'removal retained Bash state or links'
[[ "$(sha256sum "$home/.config/opencode/opencode.json")" == "$opencode_hash" ]] || fail 'Bash lifecycle changed OpenCode data'
pass

# Native append remains additive, recovers complete refresh loss, and removes from the refreshed baseline.
home="$TEST_ROOT/home-native"
mkdir "$home"
printf 'native baseline\n' > "$home/.bashrc"
chmod 0600 "$home/.bashrc"
run_area_fixture "$home" omarchy apply
[[ "$(< "$home/.bashrc")" == native\ baseline* ]] || fail 'native baseline was replaced'
printf 'refreshed native baseline without newline' > "$home/.bashrc"
chmod 0640 "$home/.bashrc"
run_area_fixture "$home" omarchy apply
printf 'refreshed native baseline without newline' > "$TEST_ROOT/native.refreshed"
chmod 0640 "$TEST_ROOT/native.refreshed"
run_area_fixture "$home" omarchy remove
assert_same "$home/.bashrc" "$TEST_ROOT/native.refreshed"
[[ "$(stat -c %a -- "$home/.bashrc")" == 640 ]] || fail 'native removal changed refreshed mode'
pass

# Bash-specific ownership checks reject aliases and extra user candidates without executing them.
# This section sources the production libraries into the current shell and mutates HOME, PATH,
# and exported test knobs; snapshot them so the sections that follow run under the harness
# environment again (the original stage file let this leak because nothing else followed).
shell_saved_home="$HOME"
shell_saved_path="$PATH"
SCRIPT_NAME=stage6-shell-test
DOTFILES_DIR="$REPO_DIR"
HOME="$TEST_ROOT/home-owner"
TARGET_ROOT="$HOME"
mkdir -p "$HOME/.local/share/dotfiles/bin" "$TEST_ROOT/owner-bin" "$TEST_ROOT/shadow-bin"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/engine.sh"
source "$REPO_DIR/lib/provisioning.sh"
source "$REPO_DIR/lib/areas/bash.sh"
trap - EXIT INT TERM
ln -s "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/bat" "$HOME/.local/share/dotfiles/bin/bat"
ln -s "$REPO_DIR/packages/generic/bash/.local/share/dotfiles/bin/fd" "$HOME/.local/share/dotfiles/bin/fd"
for command_name in fzf zoxide eza rg batcat fdfind; do printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/owner-bin/$command_name"; chmod 0755 "$TEST_ROOT/owner-bin/$command_name"; done
cat > "$TEST_ROOT/dpkg-query" <<SCRIPT
#!/usr/bin/env bash
case "\$2" in
  */fzf) package=fzf ;; */zoxide) package=zoxide ;; */eza) package=eza ;; */rg) package=ripgrep ;;
  */batcat) package=bat ;; */fdfind) package=fd-find ;; *) exit 1 ;;
esac
printf '%s: %s\n' "\$package" "\$2"
SCRIPT
chmod 0755 "$TEST_ROOT/dpkg-query"
DOTFILES_TESTING=1
DOTFILES_TEST_BASH_DISTRO_BIN="$TEST_ROOT/owner-bin"
DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/dpkg-query"
PATH="$HOME/.local/share/dotfiles/bin:$TEST_ROOT/owner-bin:/usr/bin:/bin"
export DOTFILES_TESTING DOTFILES_TEST_BASH_DISTRO_BIN DOTFILES_TEST_DPKG_QUERY PATH
bash_validate_distro_command fzf fzf || fail 'approved distro ownership was rejected'
bash_validate_wrapper bat bat "$HOME/.local/share/dotfiles/bin/bat" bat batcat || fail 'approved bat wrapper ownership was rejected'
shopt -s expand_aliases
alias fzf='printf invoked > "$TEST_ROOT/rejected-invoked"'
set +e
TEST_OUTPUT="$(bash_validate_distro_command fzf fzf 2>&1)"
status=$?
set -e
unalias fzf
[[ "$status" != 0 ]] || fail 'alias shadow was accepted'
assert_contains "$TEST_OUTPUT" 'shadowed by a shell alias'
[[ ! -e "$TEST_ROOT/rejected-invoked" ]] || fail 'rejected alias was executed'
printf '#!/usr/bin/env bash\nprintf invoked > %q\n' "$TEST_ROOT/rejected-invoked" > "$TEST_ROOT/shadow-bin/fzf"
chmod 0755 "$TEST_ROOT/shadow-bin/fzf"
PATH="$HOME/.local/share/dotfiles/bin:$TEST_ROOT/owner-bin:$TEST_ROOT/shadow-bin:/usr/bin:/bin"
set +e
TEST_OUTPUT="$(bash_validate_distro_command fzf fzf 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'additional user candidate was accepted'
[[ ! -e "$TEST_ROOT/rejected-invoked" ]] || fail 'rejected executable shadow was executed'
pass

# Restore the harness cleanup trap and the environment mutated by the ownership section.
trap cleanup_test EXIT
HOME="$shell_saved_home"
PATH="$shell_saved_path"
unset DOTFILES_TESTING DOTFILES_TEST_BASH_DISTRO_BIN DOTFILES_TEST_DPKG_QUERY

# An apply fault after attachment insertion restores links, startup bytes, mode, and state.
home="$TEST_ROOT/home-fault"
mkdir "$home"
printf 'fault original without newline' > "$home/.bashrc"
chmod 0640 "$home/.bashrc"
cp -a "$home/.bashrc" "$TEST_ROOT/fault.original"
set +e
TEST_OUTPUT="$(HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
  SCRIPT_NAME=stage6-shell-test SELECTED_PROFILE=generic MODE=apply DOTFILES_TESTING=1 \
  DOTFILES_TEST_FAIL_AT=bash-after-attachments bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/bash.sh"
    AREA_ORDER=(git bash tmux nvim zsh)
    AREA_STATUS=([git]=ready [bash]=framework [tmux]=framework [nvim]=framework [zsh]=framework)
    run_controlled_bash() { :; }
    preflight_bash
    apply_bash
  ' 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'injected Bash apply fault succeeded'
assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'bash'"
assert_same "$home/.bashrc" "$TEST_ROOT/fault.original"
[[ "$(stat -c %a -- "$home/.bashrc")" == 640 ]] || fail 'fault rollback changed startup mode'
[[ ! -e "$home/.local/state/dotfiles/v1/bash.json" && ! -e "$home/.config" ]] || fail 'fault rollback retained links or state'
pass

# ---------------------------------------------------------------------------
# Bash startup matrix and ownership sections (from stage6_matrix_test.sh)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# zsh sections (from stage6_shell_test.sh)
# ---------------------------------------------------------------------------

make_zsh_area_fixture() {
  local name="$1" home checkout old relative
  home="$TEST_ROOT/zsh-home-$name"
  checkout="$TEST_ROOT/zsh-checkout-$name"
  old="$TEST_ROOT/zsh-old-$name"
  mkdir -p "$home/fake-bin" "$home/.config" "$home/.local/share/zinit" \
    "$checkout/packages/common/zsh" "$checkout/profiles" "$checkout/manifests" \
    "$checkout/lib/stow-preflight-target" "$old"
  cp -a "$REPO_DIR/packages/common/zsh/." "$checkout/packages/common/zsh/"
  cp -a "$REPO_DIR/.zshrc" "$REPO_DIR/.zsh_aliases" "$REPO_DIR/.p10k.zsh" \
    "$REPO_DIR/.zsh_aliases.local" "$checkout/"
  printf 'zsh common/zsh\n' > "$checkout/profiles/generic.conf"
  printf 'fixture local aliases\n' > "$checkout/.zsh_aliases.local"
  cp -a "$checkout/.zshrc" "$checkout/.zsh_aliases" "$checkout/.p10k.zsh" \
    "$checkout/.zsh_aliases.local" "$old/"
  : > "$checkout/lib/stow-preflight-target/.keep"
  jq -cn --arg home "$home" --arg root "$old" '
    {schema_version:1,hosts:[{id:"zsh-fixture",status:"reviewed",home:$home,checkout_root:$root,
      platform:"fixture",scan_scope:"fixture",records:[
        [".p10k.zsh",".p10k.zsh","zsh","tracked","replace-stage-6"],
        [".zsh_aliases",".zsh_aliases","zsh","tracked","replace-stage-6"],
        [".zsh_aliases.local",".zsh_aliases.local","zsh","ignored","migrate-local-stage-6"],
        [".zshrc",".zshrc","zsh","tracked","replace-stage-6"]],blockers:[]}]}' \
    > "$checkout/manifests/legacy-links.json"
  ln -s "$old/.zshrc" "$home/.zshrc"
  relative="$(realpath -m --relative-to="$home" -- "$old/.zsh_aliases")"
  ln -s "$relative" "$home/.zsh_aliases"
  ln -s "$old/.p10k.zsh" "$home/.p10k.zsh"
  relative="$(realpath -m --relative-to="$home" -- "$old/.zsh_aliases.local")"
  ln -s "$relative" "$home/.zsh_aliases.local"
  printf '. "$HOME/.cargo/env"\n\n# Vite+ bin (https://viteplus.dev)\n. "$HOME/.vite-plus/env"\n\n# opencode\nexport PATH=/fixture/.opencode/bin:$PATH\n' \
    > "$home/.zshenv"
  chmod 0640 "$home/.zshenv"
  printf 'untouched local rc\n' > "$home/.zshrc.local"
  printf 'retained history\n' > "$home/.zsh_history"
  mkdir -p "$home/.local/share/zinit/zinit.git"
  printf 'retained zinit\n' > "$home/.local/share/zinit/zinit.git/fixture"
  cat > "$home/fake-bin/chsh" <<SCRIPT
#!/usr/bin/env bash
printf invoked > "$home/chsh-invoked"
exit 99
SCRIPT
  chmod 0755 "$home/fake-bin/chsh"
  install_network_sentinels "$home" no-git
  ZSH_FIXTURE_HOME="$home"
  ZSH_FIXTURE_CHECKOUT="$checkout"
  ZSH_FIXTURE_OLD="$old"
}

run_zsh_area_fixture() {
  local home="$1" checkout="$2" operation="$3" fail_at="${4:-}" hold_at="${5:-}" hold_dir="${6:-}" mode=apply
  [[ "$operation" != remove ]] || mode=remove
  [[ "$operation" != check ]] || mode=check
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$checkout" DOTFILES_DIR="$checkout" \
    SCRIPT_NAME=stage6-shell-test SELECTED_PROFILE=generic MODE="$mode" SHELL=/usr/bin/zsh \
    DOTFILES_TESTING=1 DOTFILES_TEST_FAIL_AT="$fail_at" DOTFILES_TEST_HOLD_AT="$hold_at" \
    DOTFILES_TEST_HOLD_DIR="$hold_dir" PATH="$home/fake-bin:/usr/bin:/bin" \
    bash -c '
      set -Eeuo pipefail
      source "'$REPO_DIR'/lib/common.sh"
      source "'$REPO_DIR'/lib/engine.sh"
      source "'$REPO_DIR'/lib/areas/zsh.sh"
      AREA_ORDER=(git bash tmux nvim zsh)
      AREA_STATUS=([git]=ready [bash]=framework [tmux]=framework [nvim]=framework [zsh]=framework)
      if [[ "$MODE" == remove ]]; then
        remove_zsh
      elif [[ "$MODE" == check ]]; then
        preflight_zsh
      else
        preflight_zsh
        apply_zsh
      fi
    '
}

# Package copies are frozen outside the reviewed local source and Vite+ changes.
assert_same "$REPO_DIR/.zsh_aliases" "$REPO_DIR/packages/common/zsh/.zsh_aliases"
assert_same "$REPO_DIR/.p10k.zsh" "$REPO_DIR/packages/common/zsh/.p10k.zsh"
[[ ! -e "$REPO_DIR/packages/common/zsh/.zsh_aliases.local" && \
  ! -e "$REPO_DIR/packages/common/zsh/.config/dotfiles/local/zsh_aliases.zsh" ]] || \
  fail 'zsh package contains host-local data'
expected_zshrc="$TEST_ROOT/expected.zshrc"
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == '# Vite+' ]]; then
    IFS= read -r _
    IFS= read -r _
  elif [[ "$line" == '[[ -f ~/.zsh_aliases.local && ! -L ~/.zsh_aliases.local && -O ~/.zsh_aliases.local && -r ~/.zsh_aliases.local ]] && \' ]]; then
    IFS= read -r _
    printf '%s\n' \
      '[[ -f "$HOME/.config/dotfiles/local/zsh_aliases.zsh" && \' \
      '  ! -L "$HOME/.config/dotfiles/local/zsh_aliases.zsh" && \' \
      '  -O "$HOME/.config/dotfiles/local/zsh_aliases.zsh" && \' \
      '  -r "$HOME/.config/dotfiles/local/zsh_aliases.zsh" ]] && \' \
      '  source "$HOME/.config/dotfiles/local/zsh_aliases.zsh"' >> "$expected_zshrc"
  else
    printf '%s\n' "$line" >> "$expected_zshrc"
  fi
done < "$REPO_DIR/.zshrc"
assert_same "$expected_zshrc" "$REPO_DIR/packages/common/zsh/.zshrc"
! grep -qF '.fzf.zsh' "$REPO_DIR/packages/common/zsh/.zshrc" || \
  fail 'managed zsh sources the unowned legacy FZF hook'
! grep -qF '.fzf/bin' "$REPO_DIR/packages/common/zsh/.zshrc" || \
  fail 'managed zsh restores the unowned legacy FZF path'
zsh -n "$REPO_DIR/packages/common/zsh/.zshrc" "$REPO_DIR/packages/common/zsh/.zsh_aliases" \
  "$REPO_DIR/packages/common/zsh/.p10k.zsh" || fail 'packaged zsh syntax is invalid'
pass

# Full migration preserves exact host bytes, records distinct backups, converges, and retains on remove.
make_zsh_area_fixture lifecycle
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
zsh_old="$ZSH_FIXTURE_OLD"
cp -a "$zsh_home/.zshenv" "$TEST_ROOT/zshenv.original"
cp -a "$zsh_home/.zshrc.local" "$TEST_ROOT/zshrc-local.original"
printf '. "$HOME/.cargo/env"\n\n\n# opencode\nexport PATH=/fixture/.opencode/bin:$PATH\n' > "$TEST_ROOT/zshenv.expected"
chmod 0640 "$TEST_ROOT/zshenv.expected"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
[[ -L "$zsh_home/.zshrc" && -L "$zsh_home/.zsh_aliases" && -L "$zsh_home/.p10k.zsh" ]] || \
  fail 'zsh package links were not deployed'
[[ ! -e "$zsh_home/.zsh_aliases.local" && ! -L "$zsh_home/.zsh_aliases.local" ]] || \
  fail 'legacy local-alias link survived migration'
[[ -f "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" && \
  ! -L "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ]] || fail 'central zsh local aliases are not a real file'
assert_same "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" "$zsh_old/.zsh_aliases.local"
assert_same "$zsh_home/.zshenv" "$TEST_ROOT/zshenv.expected"
[[ "$(stat -c %a -- "$zsh_home/.zshenv")" == 640 ]] || fail '.zshenv migration changed its mode'
assert_same "$zsh_home/.zshrc.local" "$TEST_ROOT/zshrc-local.original"
zsh_ledger="$zsh_home/.local/state/dotfiles/v1/migrations.json"
jq -e '(.migrations | length) == 2 and
  ([.migrations[].id] | sort) == ["zsh-local-alias-v1","zsh-vite-retirement-v1"] and
  ([.migrations[].backups[]] | unique | length) == 2' "$zsh_ledger" >/dev/null || \
  fail 'zsh migrations do not have distinct retained ledger records'
local_backup="$(jq -r '.migrations[] | select(.id == "zsh-local-alias-v1") | .backups[0]' "$zsh_ledger")"
vite_backup="$(jq -r '.migrations[] | select(.id == "zsh-vite-retirement-v1") | .backups[0]' "$zsh_ledger")"
  assert_same "$zsh_home/$local_backup" "$zsh_old/.zsh_aliases.local"
  assert_same "$zsh_home/$vite_backup" "$TEST_ROOT/zshenv.original"
[[ "$(stat -c %a -- "$zsh_home/$local_backup")" == 600 && \
  "$(stat -c %a -- "$zsh_home/$vite_backup")" == 600 ]] || fail 'zsh migration backups are not mode 0600'
jq -e --arg local "$local_backup" --arg vite "$vite_backup" \
  '(.backups | sort) == ([$local,$vite] | sort)' "$zsh_home/.local/state/dotfiles/v1/zsh.json" >/dev/null || \
  fail 'zsh state does not record both retained migration backups'
ledger_hash="$(sha256sum "$zsh_ledger")"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
[[ "$(sha256sum "$zsh_ledger")" == "$ledger_hash" ]] || fail 'zsh reapply changed the completed migration ledger'
printf 'drift\n' >> "$zsh_home/$vite_backup"
set +e
TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" check 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'zsh accepted a drifted retained migration backup'
assert_contains "$TEST_OUTPUT" 'retained zsh migration backup hash has drifted'
cp "$TEST_ROOT/zshenv.original" "$zsh_home/$vite_backup"
chmod 0600 "$zsh_home/$vite_backup"
chmod 0644 "$zsh_home/$local_backup"
set +e
TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" check 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'zsh accepted an unsafe retained migration backup mode'
assert_contains "$TEST_OUTPUT" 'retained zsh migration backup has an unsafe mode'
chmod 0600 "$zsh_home/$local_backup"
ln -s "$zsh_old/.zsh_aliases.local" "$zsh_home/.zsh_aliases.local"
state_hash="$(sha256sum "$zsh_home/.local/state/dotfiles/v1/zsh.json")"
set +e
TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'completed local-alias migration accepted a reappeared source'
assert_contains "$TEST_OUTPUT" 'retired source reappeared'
[[ "$(sha256sum "$zsh_home/.local/state/dotfiles/v1/zsh.json")" == "$state_hash" ]] || \
  fail 'reappeared-source refusal mutated zsh state'
rm "$zsh_home/.zsh_aliases.local"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" remove
[[ ! -e "$zsh_home/.local/state/dotfiles/v1/zsh.json" && ! -e "$zsh_home/.zshrc" && \
  ! -e "$zsh_home/.zsh_aliases" && ! -e "$zsh_home/.p10k.zsh" ]] || fail 'zsh removal retained managed links or state'
[[ -f "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" && -f "$zsh_ledger" && \
  -f "$zsh_home/$local_backup" && -f "$zsh_home/$vite_backup" && \
  -f "$zsh_home/.zsh_history" && -f "$zsh_home/.local/share/zinit/zinit.git/fixture" ]] || \
  fail 'zsh removal deleted retained local, migration, history, or Zinit data'
assert_same "$zsh_home/.zshenv" "$TEST_ROOT/zshenv.expected"
assert_same "$zsh_home/.zshrc.local" "$TEST_ROOT/zshrc-local.original"
[[ ! -e "$zsh_home/chsh-invoked" ]] || fail 'zsh lifecycle invoked chsh'
pass

# Local target collisions and partial Vite+ blocks fail during preflight without mutation.
for collision in divergent symlink directory fifo; do
  make_zsh_area_fixture "collision-$collision"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  mkdir -p "$zsh_home/.config/dotfiles/local"
  case "$collision" in
    divergent) printf 'divergent aliases\n' > "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ;;
    symlink) ln -s "$TEST_ROOT" "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ;;
    directory) mkdir "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ;;
    fifo) mkfifo "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ;;
  esac
  cp -a "$zsh_home" "$TEST_ROOT/collision-$collision.original"
  set +e
  TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
  status=$?
  set -e
  [[ "$status" != 0 ]] || fail "zsh accepted $collision central local-alias target"
  if [[ "$collision" == fifo ]]; then
    [[ -p "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" && -L "$zsh_home/.zshrc" && \
      ! -e "$zsh_home/.local/state/dotfiles/v1/zsh.json" ]] || fail 'FIFO local-alias refusal mutated HOME'
  else
    diff --no-dereference -r "$zsh_home" "$TEST_ROOT/collision-$collision.original" >/dev/null || \
      fail "$collision local-alias refusal mutated HOME"
  fi
done
make_zsh_area_fixture identical
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
zsh_old="$ZSH_FIXTURE_OLD"
mkdir -p "$zsh_home/.config/dotfiles/local"
cp "$zsh_old/.zsh_aliases.local" "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh"
chmod 0600 "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
[[ "$(stat -c %a -- "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh")" == 600 ]] || \
  fail 'identical central local-alias reuse rewrote its mode'

make_zsh_area_fixture no-local-source
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
rm "$zsh_home/.zsh_aliases.local"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
[[ ! -e "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ]] || \
  fail 'zsh fabricated central local aliases without a reviewed source'
jq -e 'all(.migrations[]; .id != "zsh-local-alias-v1")' \
  "$zsh_home/.local/state/dotfiles/v1/migrations.json" >/dev/null || \
  fail 'zsh recorded a local-alias migration without a source'

make_zsh_area_fixture broken-reviewed
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
zsh_old="$ZSH_FIXTURE_OLD"
rm "$zsh_old/.zshrc" "$zsh_old/.zsh_aliases" "$zsh_old/.p10k.zsh" "$zsh_old/.zsh_aliases.local"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
assert_same "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" "$zsh_checkout/.zsh_aliases.local"

make_zsh_area_fixture redirected-reviewed
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
zsh_old="$ZSH_FIXTURE_OLD"
printf 'redirected source\n' > "$TEST_ROOT/redirected-reviewed-zshrc"
rm "$zsh_old/.zshrc"
ln -s "$TEST_ROOT/redirected-reviewed-zshrc" "$zsh_old/.zshrc"
cp -a "$zsh_home" "$TEST_ROOT/redirected-reviewed.original"
set +e
TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'zsh accepted a reviewed lexical link resolving to an unapproved target'
diff --no-dereference -r "$zsh_home" "$TEST_ROOT/redirected-reviewed.original" >/dev/null || \
  fail 'redirected reviewed-link refusal mutated HOME'

# Current-checkout reviewed links are accepted in both absolute and relative form.
for link_style in absolute relative; do
  make_zsh_area_fixture "current-$link_style"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  jq --arg root "$zsh_checkout" '(.hosts[0].checkout_root)=$root' \
    "$zsh_checkout/manifests/legacy-links.json" > "$zsh_checkout/manifests/legacy-links.json.tmp"
  mv "$zsh_checkout/manifests/legacy-links.json.tmp" "$zsh_checkout/manifests/legacy-links.json"
  for relative in .zshrc .zsh_aliases .p10k.zsh .zsh_aliases.local; do
    rm "$zsh_home/$relative"
    target="$zsh_checkout/$relative"
    if [[ "$link_style" == relative ]]; then
      target="$(realpath -m --relative-to="$zsh_home" -- "$target")"
    fi
    ln -s "$target" "$zsh_home/$relative"
  done
  run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
  [[ ! -e "$zsh_home/.zsh_aliases.local" && -L "$zsh_home/.zshrc" ]] || \
    fail "current-checkout $link_style reviewed links did not migrate"
done

# Unrelated regular files and symlinks remain blocking and byte-preserved.
for unrelated in regular symlink; do
  make_zsh_area_fixture "unrelated-$unrelated"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  rm "$zsh_home/.zshrc"
  if [[ "$unrelated" == regular ]]; then
    printf 'unrelated zshrc\n' > "$zsh_home/.zshrc"
  else
    printf 'unrelated target\n' > "$TEST_ROOT/unrelated-zshrc"
    ln -s "$TEST_ROOT/unrelated-zshrc" "$zsh_home/.zshrc"
  fi
  cp -a "$zsh_home" "$TEST_ROOT/unrelated-$unrelated.original"
  set +e
  TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
  status=$?
  set -e
  [[ "$status" != 0 ]] || fail "zsh accepted unrelated $unrelated startup data"
  diff --no-dereference -r "$zsh_home" "$TEST_ROOT/unrelated-$unrelated.original" >/dev/null || \
    fail "unrelated $unrelated refusal mutated HOME"
done

make_zsh_area_fixture vite-partial
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
printf '. "$HOME/.cargo/env"\n\n# Vite+ bin (https://viteplus.dev)\n\n# opencode\n' > "$zsh_home/.zshenv"
cp -a "$zsh_home" "$TEST_ROOT/vite-partial.original"
set +e
TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'zsh accepted a partial reviewed Vite+ block'
assert_contains "$TEST_OUTPUT" 'partial or modified reviewed Vite+ block'
diff --no-dereference -r "$zsh_home" "$TEST_ROOT/vite-partial.original" >/dev/null || \
  fail 'partial Vite+ refusal mutated HOME'

for vite_shape in modified duplicate; do
  make_zsh_area_fixture "vite-$vite_shape"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  if [[ "$vite_shape" == modified ]]; then
    printf '# Vite+ bin (https://viteplus.dev)\n. "$HOME/.vite-plus/changed"\n' > "$zsh_home/.zshenv"
  else
    printf '# Vite+ bin (https://viteplus.dev)\n. "$HOME/.vite-plus/env"\n# Vite+ bin (https://viteplus.dev)\n. "$HOME/.vite-plus/env"\n' > "$zsh_home/.zshenv"
  fi
  cp -a "$zsh_home" "$TEST_ROOT/vite-$vite_shape.original"
  set +e
  TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
  status=$?
  set -e
  [[ "$status" != 0 ]] || fail "zsh accepted $vite_shape Vite+ block"
  diff --no-dereference -r "$zsh_home" "$TEST_ROOT/vite-$vite_shape.original" >/dev/null || \
    fail "$vite_shape Vite+ refusal mutated HOME"
done

make_zsh_area_fixture vite-nul
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
printf '# Vite+ bin (https://viteplus.dev)\n. "$HOME/.vite-plus/env"\n\0unrelated\n' > "$zsh_home/.zshenv"
cp -a "$zsh_home" "$TEST_ROOT/vite-nul.original"
set +e
TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'zsh accepted NUL-bearing .zshenv data'
assert_contains "$TEST_OUTPUT" 'contains NUL bytes and cannot be edited safely'
diff --no-dereference -r "$zsh_home" "$TEST_ROOT/vite-nul.original" >/dev/null || \
  fail 'NUL-bearing Vite+ refusal mutated HOME'

race_home="$TEST_ROOT/backup-race-home"
race_hold="$TEST_ROOT/backup-race-hold"
mkdir -p "$race_home/backups" "$race_hold"
printf 'source bytes\n' > "$race_home/source"
HOME="$race_home" TARGET_ROOT="$race_home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage6-shell-test \
  DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=before-atomic-rename DOTFILES_TEST_HOLD_DIR="$race_hold" \
  bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/areas/zsh.sh"
    write_file_copy_no_clobber "$HOME/source" "$HOME/backups/retained" 0600
  ' > "$TEST_ROOT/backup-race.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$race_hold/before-atomic-rename.ready" ]] && break
  sleep 0.01
done
[[ -e "$race_hold/before-atomic-rename.ready" ]] || fail 'no-clobber backup test did not reach the rename hold'
printf 'collision bytes\n' > "$race_home/backups/retained"
: > "$race_hold/before-atomic-rename.release"
if wait "$race_pid"; then fail 'retained backup no-clobber race unexpectedly overwrote a collision'; fi
[[ "$(< "$race_home/backups/retained")" == 'collision bytes' ]] || fail 'retained backup race changed collision bytes'
pass

# Newly installed backups and destructive sources are revalidated before commit.
for tamper in local-backup vite-backup vite-source; do
  make_zsh_area_fixture "creation-$tamper"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  hold_dir="$TEST_ROOT/creation-$tamper-hold"
  mkdir "$hold_dir"
  cp -a "$zsh_home" "$TEST_ROOT/creation-$tamper.original"
  if [[ "$tamper" == local-backup ]]; then
    hold_point=after-zsh-local-backup-install
  else
    hold_point=after-zsh-vite-backup-install
  fi
  run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply '' "$hold_point" "$hold_dir" \
    > "$TEST_ROOT/creation-$tamper.log" 2>&1 &
  tamper_pid=$!
  for _ in $(seq 1 500); do
    [[ -e "$hold_dir/$hold_point.ready" ]] && break
    sleep 0.01
  done
  [[ -e "$hold_dir/$hold_point.ready" ]] || fail "$tamper backup test did not reach its creation hold"
  if [[ "$tamper" == local-backup ]]; then
    backup_paths=("$zsh_home"/.local/state/dotfiles/v1/backups/zsh/zsh-local-alias-v1-*.bak)
    ((${#backup_paths[@]} == 1)) || fail 'local backup tamper fixture did not find exactly one new backup'
    printf 'tampered local backup\n' > "${backup_paths[0]}"
  elif [[ "$tamper" == vite-backup ]]; then
    backup_paths=("$zsh_home"/.local/state/dotfiles/v1/backups/zsh/zsh-vite-retirement-v1-*.bak)
    ((${#backup_paths[@]} == 1)) || fail 'Vite backup tamper fixture did not find exactly one new backup'
    chmod 0644 "${backup_paths[0]}"
  else
    printf 'concurrent source replacement\n' > "$zsh_home/.zshenv"
  fi
  : > "$hold_dir/$hold_point.release"
  set +e
  wait "$tamper_pid"
  status=$?
  set -e
  if [[ "$tamper" == vite-source ]]; then
    [[ "$status" != 0 ]] || fail 'concurrent .zshenv source replacement unexpectedly committed'
  else
    [[ "$status" == 70 ]] || fail "$tamper collision did not reserve rollback status 70: $status"
  fi
  [[ -L "$zsh_home/.zshrc" && -L "$zsh_home/.zsh_aliases" && -L "$zsh_home/.p10k.zsh" && \
    -L "$zsh_home/.zsh_aliases.local" && ! -e "$zsh_home/.local/state/dotfiles/v1/zsh.json" && \
    ! -e "$zsh_home/.local/state/dotfiles/v1/migrations.json" && \
    ! -e "$zsh_home/.config/dotfiles/local/zsh_aliases.zsh" ]] || \
    fail "$tamper collision did not restore non-conflicting zsh paths"
  if [[ "$tamper" == local-backup ]]; then
    [[ "$(< "${backup_paths[0]}")" == 'tampered local backup' ]] || fail 'tampered local backup was not preserved'
    assert_same "$zsh_home/.zshenv" "$TEST_ROOT/creation-$tamper.original/.zshenv"
  elif [[ "$tamper" == vite-backup ]]; then
    [[ "$(stat -c %a -- "${backup_paths[0]}")" == 644 ]] || fail 'concurrently changed Vite backup mode was not preserved'
    assert_same "$zsh_home/.zshenv" "$TEST_ROOT/creation-$tamper.original/.zshenv"
  else
    [[ "$(< "$zsh_home/.zshenv")" == 'concurrent source replacement' ]] || \
      fail 'concurrent .zshenv replacement was not preserved'
  fi
done
pass

# Preflight-to-mutation races preserve replacement .zshenv data and local symlinks.
make_zsh_area_fixture zshenv-race
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
hold_dir="$TEST_ROOT/zshenv-race-hold"
mkdir "$hold_dir"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply '' before-zshenv-replacement-quarantine "$hold_dir" \
  > "$TEST_ROOT/zshenv-race.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$hold_dir/before-zshenv-replacement-quarantine.ready" ]] && break
  sleep 0.01
done
[[ -e "$hold_dir/before-zshenv-replacement-quarantine.ready" ]] || fail '.zshenv race did not reach its hold'
mv "$zsh_home/.zshenv" "$zsh_home/.zshenv.preflight-object"
printf 'concurrent zshenv data\n' > "$zsh_home/.zshenv"
: > "$hold_dir/before-zshenv-replacement-quarantine.release"
if wait "$race_pid"; then fail '.zshenv replacement race unexpectedly committed'; fi
[[ "$(< "$zsh_home/.zshenv")" == 'concurrent zshenv data' && \
  -f "$zsh_home/.zshenv.preflight-object" && ! -e "$zsh_home/.local/state/dotfiles/v1/zsh.json" ]] || \
  fail '.zshenv replacement race lost concurrent or preflight data'

make_zsh_area_fixture zsh-local-race
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
printf 'concurrent local target\n' > "$TEST_ROOT/zsh-local-race-target"
hold_dir="$TEST_ROOT/zsh-local-race-hold"
mkdir "$hold_dir"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply '' before-zsh-local-quarantine "$hold_dir" \
  > "$TEST_ROOT/zsh-local-race.log" 2>&1 &
race_pid=$!
for _ in $(seq 1 500); do
  [[ -e "$hold_dir/before-zsh-local-quarantine.ready" ]] && break
  sleep 0.01
done
[[ -e "$hold_dir/before-zsh-local-quarantine.ready" ]] || fail 'zsh local-link race did not reach its hold'
mv "$zsh_home/.zsh_aliases.local" "$zsh_home/.zsh_aliases.local.approved-object"
ln -s "$TEST_ROOT/zsh-local-race-target" "$zsh_home/.zsh_aliases.local"
: > "$hold_dir/before-zsh-local-quarantine.release"
if wait "$race_pid"; then fail 'zsh local-link race unexpectedly committed'; fi
[[ -L "$zsh_home/.zsh_aliases.local" && \
  "$(readlink "$zsh_home/.zsh_aliases.local")" == "$TEST_ROOT/zsh-local-race-target" && \
  -L "$zsh_home/.zsh_aliases.local.approved-object" && \
  ! -e "$zsh_home/.local/state/dotfiles/v1/zsh.json" ]] || \
  fail 'zsh local-link race lost an approved or concurrent symlink'
pass

# Every exposed zsh apply fault restores links, local data, .zshenv bytes/mode, ledger, and state.
zsh_faults=(
  zsh-after-local-destination zsh-after-local-backup zsh-after-legacy-links zsh-after-stow
  zsh-after-active-validation zsh-after-local-source-removal zsh-after-vite-backup
  zsh-after-vite-retirement zsh-after-local-ledger zsh-after-vite-ledger zsh-after-state
)
for point in "${zsh_faults[@]}"; do
  make_zsh_area_fixture "fault-$point"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  cp -a "$zsh_home" "$TEST_ROOT/$point.original"
  set +e
  TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply "$point" 2>&1)"
  status=$?
  set -e
  [[ "$status" != 0 ]] || fail "injected zsh fault succeeded: $point"
  assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'zsh'"
  diff --no-dereference -r "$zsh_home" "$TEST_ROOT/$point.original" >/dev/null || \
    fail "zsh rollback did not restore complete HOME at $point"
done
pass

# Removal faults restore deployed links and state without touching retained migration results.
for point in zsh-remove-after-links zsh-remove-after-state; do
  make_zsh_area_fixture "remove-fault-$point"
  zsh_home="$ZSH_FIXTURE_HOME"
  zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
  run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
  cp -a "$zsh_home" "$TEST_ROOT/$point.original"
  set +e
  TEST_OUTPUT="$(run_zsh_area_fixture "$zsh_home" "$zsh_checkout" remove "$point" 2>&1)"
  status=$?
  set -e
  [[ "$status" != 0 ]] || fail "injected zsh removal fault succeeded: $point"
  assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'zsh'"
  diff --no-dereference -r "$zsh_home" "$TEST_ROOT/$point.original" >/dev/null || \
    fail "zsh removal rollback did not restore complete HOME at $point"
done
pass

# Missing Zinit performs only the controlled clone; an initialized entrypoint never invokes git.
zinit_rc="$REPO_DIR/packages/common/zsh/.zshrc"
zinit_home="$TEST_ROOT/zinit-missing"
mkdir -p "$zinit_home/fake-bin" "$zinit_home/.config/dotfiles/local"
install_network_sentinels "$zinit_home" no-git
printf 'typeset -g ZSH_LOCAL_FIXTURE=loaded\n' > "$zinit_home/.config/dotfiles/local/zsh_aliases.zsh"
cat > "$zinit_home/fake-bin/git" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$1" == clone && "$2" == https://github.com/zdharma-continuum/zinit.git ]] || exit 98
printf '%s\n' "$*" > "$HOME/git-clone-trace"
mkdir -p "$3"
cat > "$3/zinit.zsh" <<'ZINIT'
zinit() { print -r -- "$*" >> "$HOME/zinit-calls"; }
ZINIT
SCRIPT
chmod 0755 "$zinit_home/fake-bin/git"
HOME="$zinit_home" PATH="$zinit_home/fake-bin:/usr/bin:/bin" run_network_isolated zsh -f -c \
  "source '$zinit_rc'; [[ \$ZSH_LOCAL_FIXTURE == loaded ]]" || fail 'missing-Zinit controlled first start failed'
[[ "$(< "$zinit_home/git-clone-trace")" == clone\ https://github.com/zdharma-continuum/zinit.git\ "$zinit_home/.local/share/zinit/zinit.git" ]] || \
  fail 'missing Zinit used an unexpected clone path'

zinit_home="$TEST_ROOT/zinit-existing"
mkdir -p "$zinit_home/fake-bin" "$zinit_home/.local/share/zinit/zinit.git"
install_network_sentinels "$zinit_home" no-git
cat > "$zinit_home/.local/share/zinit/zinit.git/zinit.zsh" <<'ZINIT'
zinit() {
  print -r -- "$*" >> "$HOME/zinit-calls"
  [[ "$1" != light ]] || git clone https://plugins.invalid/missing.git "$HOME/plugin-download"
}
ZINIT
cat > "$zinit_home/fake-bin/git" <<SCRIPT
#!/usr/bin/env bash
printf attempted > "$zinit_home/network-attempted"
exit 99
SCRIPT
chmod 0755 "$zinit_home/fake-bin/git"
HOME="$zinit_home" PATH="$zinit_home/fake-bin:/usr/bin:/bin" run_network_isolated zsh -f -c "source '$zinit_rc'" || \
  fail 'initialized Zinit startup failed'
[[ ! -e "$zinit_home/network-attempted" ]] || fail 'initialized Zinit startup attempted clone or update'

# A complete local plugin closure is loaded with Git network protocols disabled.
zinit_home="$TEST_ROOT/zinit-complete"
mkdir -p "$zinit_home/fake-bin" "$zinit_home/.local/share/zinit/zinit.git" \
  "$zinit_home/.local/share/zinit/plugins"
for plugin in romkatv---powerlevel10k zsh-users---zsh-syntax-highlighting \
  zsh-users---zsh-autosuggestions Aloxaf---fzf-tab; do
  mkdir -p "$zinit_home/.local/share/zinit/plugins/$plugin/.git"
done
cat > "$zinit_home/.local/share/zinit/zinit.git/zinit.zsh" <<'ZINIT'
zinit() {
  [[ ${GIT_ALLOW_PROTOCOL-} == file ]] || { print unsafe-protocol >> "$HOME/network-attempted"; return 97; }
  print -r -- "$*" >> "$HOME/zinit-calls"
}
ZINIT
HOME="$zinit_home" PATH="$zinit_home/fake-bin:/usr/bin:/bin" run_network_isolated zsh -f -c "source '$zinit_rc'" || \
  fail 'complete local Zinit plugin closure failed local-only loading'
[[ ! -e "$zinit_home/network-attempted" && "$(grep -c '^light ' "$zinit_home/zinit-calls")" == 4 ]] || \
  fail 'complete Zinit plugin closure was not loaded with local-only protocol policy'

# An existing directory without a readable entrypoint is still first-start state.
zinit_home="$TEST_ROOT/zinit-missing-entrypoint"
mkdir -p "$zinit_home/fake-bin" "$zinit_home/.local/share/zinit/zinit.git"
install_network_sentinels "$zinit_home" no-git
cat > "$zinit_home/fake-bin/git" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$1" == clone && "$2" == https://github.com/zdharma-continuum/zinit.git ]] || exit 98
printf '%s\n' "$*" > "$HOME/git-clone-trace"
mkdir -p "$3"
printf 'zinit() { :; }\n' > "$3/zinit.zsh"
SCRIPT
chmod 0755 "$zinit_home/fake-bin/git"
HOME="$zinit_home" PATH="$zinit_home/fake-bin:/usr/bin:/bin" run_network_isolated zsh -f -c "source '$zinit_rc'" || \
  fail 'missing Zinit entrypoint did not use controlled first-start clone'
[[ -f "$zinit_home/git-clone-trace" ]] || fail 'missing Zinit entrypoint was treated as initialized'

# zsh tool initializers receive offline policy; Worktrunk also runs in a denied-network namespace.
zinit_home="$TEST_ROOT/zsh-offline-tools"
mkdir -p "$zinit_home/fake-bin" "$zinit_home/.local/share/zinit/zinit.git"
cat > "$zinit_home/.local/share/zinit/zinit.git/zinit.zsh" <<'ZINIT'
zinit() { :; }
ZINIT
cat > "$zinit_home/fake-bin/mise" <<'SCRIPT'
#!/usr/bin/env bash
[[ ${MISE_OFFLINE-} == 1 ]] || { printf mise-unsafe > "$HOME/network-attempted"; exit 97; }
[[ "$*" == 'activate zsh' ]] && printf 'typeset -g MISE_OFFLINE_FIXTURE=loaded\n'
SCRIPT
cat > "$zinit_home/fake-bin/wt" <<'SCRIPT'
#!/usr/bin/env bash
[[ ${MISE_OFFLINE-} == 1 ]] || { printf wt-unsafe > "$HOME/network-attempted"; exit 97; }
[[ "$*" == 'config shell init zsh' ]] && printf 'typeset -g WT_OFFLINE_FIXTURE=loaded\n'
SCRIPT
chmod 0755 "$zinit_home/fake-bin/mise" "$zinit_home/fake-bin/wt"
HOME="$zinit_home" PATH="$zinit_home/fake-bin:/usr/bin:/bin" zsh -f -c \
  "source '$zinit_rc'; [[ \$MISE_OFFLINE_FIXTURE == loaded && \$WT_OFFLINE_FIXTURE == loaded ]]" || \
  fail 'zsh offline mise or Worktrunk initialization failed'
[[ ! -e "$zinit_home/network-attempted" ]] || fail 'zsh tool initializer ran without offline enforcement'
pass

# zsh check and remove paths are sentinel-backed and never invoke login-shell mutation.
make_zsh_area_fixture offline-lifecycle
zsh_home="$ZSH_FIXTURE_HOME"
zsh_checkout="$ZSH_FIXTURE_CHECKOUT"
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" check
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" apply
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" check
run_zsh_area_fixture "$zsh_home" "$zsh_checkout" remove
[[ ! -e "$zsh_home/network-attempted" ]] || fail 'zsh check/apply/remove invoked a network sentinel'
[[ ! -e "$zsh_home/chsh-invoked" ]] || fail 'zsh check/apply/remove invoked chsh'
pass

# ---------------------------------------------------------------------------
# Ready-area gating sections (from stage6_ready_test.sh)
# ---------------------------------------------------------------------------

# Production areas.tsv now marks all five areas ready; this fixture deliberately
# reconstructs a mixed-readiness world (tmux and nvim back to framework) so the
# ready-area gating mechanism itself stays covered.
READY_REPO="$(copy_repo_fixture ready)"
set_area_status "$READY_REPO" tmux framework
set_area_status "$READY_REPO" nvim framework

home="$TEST_ROOT/home"
host="$TEST_ROOT/host"
distro_bin="$TEST_ROOT/ready-distro-bin"
sentinel_bin="$TEST_ROOT/ready-sentinels/fake-bin"
mkdir -p "$home/.config/opencode" "$home/.local/bin" \
  "$home/.local/state/dotfiles/provisioning/v1" \
  "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0" \
  "$home/.local/share/mise/installs/aqua-starship-starship" \
  "$host/etc" "$host/proc/sys/kernel" "$distro_bin"
printf 'ID=ubuntu\nVERSION_ID=24.04\n' > "$host/etc/os-release"
printf '6.6.0-microsoft-standard-WSL2\n' > "$host/proc/sys/kernel/osrelease"
printf 'preserved OpenCode fixture\n' > "$home/.config/opencode/opencode.json"

install_network_sentinels "$TEST_ROOT/ready-sentinels"
cat > "$sentinel_bin/chsh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'chsh:%s\n' "$*" >> "$HOME/chsh-attempted"
exit 97
SCRIPT
chmod 0755 "$sentinel_bin/chsh"

for name in fzf zoxide eza rg batcat fdfind; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$distro_bin/$name"
  chmod 0755 "$distro_bin/$name"
done
cat > "$TEST_ROOT/dpkg-query" <<'SCRIPT'
#!/usr/bin/env bash
case "$2" in
  */fzf) package=fzf ;; */zoxide) package=zoxide ;; */eza) package=eza ;; */rg) package=ripgrep ;;
  */batcat) package=bat ;; */fdfind) package=fd-find ;; *) exit 1 ;;
esac
printf '%s: %s\n' "$package" "$2"
SCRIPT
chmod 0755 "$TEST_ROOT/dpkg-query"

cat > "$home/.local/bin/mise" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf '2026.7.7 linux-x64\n' ;;
  activate) exit 0 ;;
  *) exit 1 ;;
esac
SCRIPT
cat > "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship" <<'SCRIPT'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && printf 'starship 1.26.0\n'
SCRIPT
chmod 0755 "$home/.local/bin/mise" \
  "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship"
ln -s "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0" \
  "$home/.local/share/mise/installs/aqua-starship-starship/1.26.0"
launcher_content="#!/usr/bin/env bash
exec $home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship \"\$@\""
printf '%s\n' "$launcher_content" > "$home/.local/bin/starship"
chmod 0755 "$home/.local/bin/starship"
mise_hash="$(sha256sum "$home/.local/bin/mise")"; mise_hash="${mise_hash%% *}"
tool_hash="$(sha256sum "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship")"; tool_hash="${tool_hash%% *}"
launcher_hash="$(printf '%s\n' "$launcher_content" | sha256sum)"; launcher_hash="${launcher_hash%% *}"
manifest_hash="$(sha256sum "$READY_REPO/manifests/provisioning.json")"; manifest_hash="${manifest_hash%% *}"
jq -cn --arg manifest "$manifest_hash" --arg mise_hash "$mise_hash" --arg tool_hash "$tool_hash" \
  --arg launcher_hash "$launcher_hash" '
  {schema_version:1,manifest_sha256:$manifest,
   tools:[
     {id:"mise",backend:"bootstrap:mise",version:"2026.7.7",platform:"linux-x86_64",
      install_root:".local/bin",executable:"mise",executable_sha256:$mise_hash},
     {id:"starship",backend:"aqua:starship/starship",version:"1.26.0",platform:"linux-x86_64",
      install_root:".local/share/dotfiles/provisioning/tools/starship/1.26.0",executable:"starship",
      executable_sha256:$tool_hash}],
   launchers:[{tool_id:"starship",destination:".local/bin/starship",content_sha256:$launcher_hash}]}' \
  > "$home/.local/state/dotfiles/provisioning/v1/receipt.json"
chmod 0600 "$home/.local/state/dotfiles/provisioning/v1/receipt.json"

cp -a "$home" "$TEST_ROOT/home-before"
run_check() {
  HOME="$home" PATH="$home/.local/bin:$distro_bin:$sentinel_bin:/usr/bin:/bin" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" DOTFILES_TEST_ARCH=x86_64 \
    DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/dpkg-query" \
    GIT_USER_NAME='Ready Fixture' GIT_USER_EMAIL=ready@example.com \
    "$READY_REPO/bootstrap.sh" --check "$@"
}
run_apply() {
  HOME="$home" PATH="$home/.local/bin:$distro_bin:$sentinel_bin:/usr/bin:/bin" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" DOTFILES_TEST_ARCH=x86_64 \
    DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/dpkg-query" \
    GIT_USER_NAME='Ready Fixture' GIT_USER_EMAIL=ready@example.com \
    "$READY_REPO/bootstrap.sh" "$@"
}

login_shell_before="$(getent passwd "$(id -un)" | cut -d: -f7)"

TEST_OUTPUT="$(run_check --area bash 2>&1)" || fail 'explicit ready Bash check failed'
[[ "$TEST_OUTPUT" == *"area 'bash' preflight passed"* ]] || fail 'explicit Bash check did not pass its area preflight'
TEST_OUTPUT="$(run_check --area zsh 2>&1)" || fail 'explicit ready zsh check failed'
[[ "$TEST_OUTPUT" == *"area 'zsh' preflight passed"* ]] || fail 'explicit zsh check did not pass its area preflight'
TEST_OUTPUT="$(run_check 2>&1)" || fail 'default ready-area check failed'
for area in git bash zsh; do
  [[ "$TEST_OUTPUT" == *"area '$area' preflight passed"* ]] || fail "default check omitted ready area $area"
done
[[ "$TEST_OUTPUT" != *"area 'tmux'"* && "$TEST_OUTPUT" != *"area 'nvim'"* ]] || \
  fail 'default check selected a framework area'
[[ ! -e "$home/network-attempted" ]] || fail 'ready-area checks invoked a network sentinel'
HOME_DIFF="$(diff --no-dereference -r "$home" "$TEST_ROOT/home-before" || true)"
[[ -z "$HOME_DIFF" ]] || { TEST_OUTPUT="$HOME_DIFF"; fail 'ready-area checks mutated fixture HOME'; }

# First-time WSL rollout is explicitly Bash-first and zsh requires a later command.
cp -a "$home" "$TEST_ROOT/home-before-sequence"
set +e
TEST_OUTPUT="$(run_apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'first default WSL apply migrated Bash and zsh together'
[[ "$TEST_OUTPUT" == *'first WSL Bash deployment must explicitly select --area bash without zsh'* ]] || \
  fail 'first default WSL refusal did not explain Bash-first sequencing'
HOME_DIFF="$(diff --no-dereference -r "$home" "$TEST_ROOT/home-before-sequence" || true)"
[[ -z "$HOME_DIFF" ]] || { TEST_OUTPUT="$HOME_DIFF"; fail 'first default WSL refusal mutated HOME'; }

run_apply --area bash >/dev/null || fail 'explicit first Bash apply failed'
[[ -f "$home/.local/state/dotfiles/v1/bash.json" && ! -e "$home/.local/state/dotfiles/v1/zsh.json" ]] || \
  fail 'explicit first Bash apply did not stop before zsh'

# A state file alone is not a recovery guarantee: first zsh apply rechecks Bash links,
# attachments, controlled startup, and ownership health before any zsh mutation.
mv "$home/.config/dotfiles/bash/rc.bash" "$home/.config/dotfiles/bash/rc.bash.degraded-link"
printf 'unrelated replacement\n' > "$home/.config/dotfiles/bash/rc.bash"
set +e
TEST_OUTPUT="$(run_apply --area zsh 2>&1)"
status=$?
set -e
[[ "$status" != 0 && "$TEST_OUTPUT" == *'existing Bash deployment is degraded'* ]] || \
  fail 'first zsh apply accepted a degraded Bash deployment'
[[ "$(< "$home/.config/dotfiles/bash/rc.bash")" == 'unrelated replacement' && \
  ! -e "$home/.local/state/dotfiles/v1/zsh.json" ]] || \
  fail 'degraded Bash refusal mutated the replacement or started zsh migration'
rm "$home/.config/dotfiles/bash/rc.bash"
mv "$home/.config/dotfiles/bash/rc.bash.degraded-link" "$home/.config/dotfiles/bash/rc.bash"
set +e
TEST_OUTPUT="$(run_apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 && "$TEST_OUTPUT" == *'first WSL zsh deployment must explicitly select --area zsh without bash'* ]] || \
  fail 'default apply deployed first-time zsh without an explicit second step'
run_apply --area zsh >/dev/null || fail 'explicit post-Bash zsh apply failed'
[[ -f "$home/.local/state/dotfiles/v1/zsh.json" ]] || fail 'explicit zsh apply did not record zsh state'
run_apply >/dev/null || fail 'later default apply failed after both shell areas were deployed'
run_apply --remove >/dev/null || fail 'ready-area fixture removal failed'

# A real WSL host with an explicit generic profile deploys and starts without the WSL adapter.
run_apply --profile generic --area bash >/dev/null || fail 'explicit generic-on-WSL Bash apply failed'
: > "$home/generic-trace"
HOME="$home" PATH="$home/.local/bin:$distro_bin:$sentinel_bin:/usr/bin:/bin" TERM=dumb HISTFILE=/dev/null \
  DOTFILES_BASH_TRACE="$home/generic-trace" bash --noprofile -i -c ':' >/dev/null 2> "$home/generic-stderr"
[[ "$(grep -c '^generic$' "$home/generic-trace")" == 1 && \
  "$(grep -c '^wsl$' "$home/generic-trace" || true)" == 0 ]] || \
  fail 'explicit generic-on-WSL startup loaded the WSL adapter or omitted generic startup'
run_apply --remove --area bash >/dev/null || fail 'explicit generic-on-WSL Bash removal failed'

login_shell_after="$(getent passwd "$(id -un)" | cut -d: -f7)"
[[ "$login_shell_after" == "$login_shell_before" ]] || fail 'login-shell value changed across check/apply/reapply/remove'
[[ ! -e "$home/chsh-attempted" ]] || fail 'ready-area lifecycle invoked chsh'
pass

printf 'PASS: %d shell domain test groups (network namespace: %s)\n' "$TEST_COUNT" "${NETWORK_NAMESPACE:-false}"
