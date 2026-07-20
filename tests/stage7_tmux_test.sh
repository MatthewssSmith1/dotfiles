#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly REAL_TMUX=/usr/bin/tmux
TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""

cleanup_test() { rm -rf -- "$TEST_ROOT"; }
trap cleanup_test EXIT
fail() { printf 'FAIL: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2; exit 1; }
pass() { ((TEST_COUNT += 1)); }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"; }
assert_same() { cmp -s -- "$1" "$2" || fail "files differ: $1 $2"; }

[[ -f "$REAL_TMUX" && ! -L "$REAL_TMUX" && -x "$REAL_TMUX" && "$($REAL_TMUX -V)" == 'tmux 3.4' ]] || \
  fail 'Stage 7 lifecycle tests require the explicit distro /usr/bin/tmux 3.4 parser'

run_tmux_area() {
  local home="$1" profile="$2" operation="$3" fail_at="${4:-}" hold_at="${5:-}" hold_dir="${6:-}" mode=apply
  [[ "$operation" != remove ]] || mode=remove
  [[ "$operation" != check ]] || mode=check
  HOME="$home" TARGET_ROOT="$home" CHECKOUT_ROOT="$REPO_DIR" DOTFILES_DIR="$REPO_DIR" \
    SCRIPT_NAME=stage7-tmux-test SELECTED_PROFILE="$profile" MODE="$mode" \
    DOTFILES_TESTING=1 DOTFILES_TEST_TMUX_BIN="$REAL_TMUX" DOTFILES_TEST_TMUX_OWNER=test-owner \
    DOTFILES_TEST_TMUX_SKIP_ACTIVE=1 DOTFILES_TEST_FAIL_AT="$fail_at" DOTFILES_TEST_HOLD_AT="$hold_at" \
    DOTFILES_TEST_HOLD_DIR="$hold_dir" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/tmux.sh"
      AREA_ORDER=(git bash tmux nvim zsh)
      AREA_STATUS=([git]=ready [bash]=ready [tmux]=framework [nvim]=framework [zsh]=ready)
      PROVISIONING_MANIFEST="$DOTFILES_DIR/manifests/provisioning.json"
      tmux_validate_exact_plugin_closure() { :; }
      if [[ "$MODE" == remove ]]; then
        remove_tmux
      elif [[ "$MODE" == check ]]; then
        preflight_tmux
      else
        preflight_tmux
        apply_tmux
      fi
    '
}

# Generic migration validates the XDG dispatcher first, records no backup, and
# leaves compatibility source, plugins, and Resurrect data untouched.
home="$TEST_ROOT/home-generic"
mkdir -p "$home/.tmux/plugins/fixture" "$home/.tmux/resurrect"
mkdir -p "$home/.local/state/dotfiles/provisioning/v1"
printf 'plugin data\n' > "$home/.tmux/plugins/fixture/data"
printf 'resurrect data\n' > "$home/.tmux/resurrect/session"
printf 'retained plugin receipt\n' > "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
ln -s "$REPO_DIR/.tmux.conf" "$home/.tmux.conf"
cp -a "$home" "$TEST_ROOT/generic-before-check"
run_tmux_area "$home" generic check >/dev/null
diff --no-dereference -r "$home" "$TEST_ROOT/generic-before-check" >/dev/null || \
  fail 'tmux check mutated the fixture HOME'
run_tmux_area "$home" generic apply >/dev/null
state="$home/.local/state/dotfiles/v1/tmux.json"
ledger="$home/.local/state/dotfiles/v1/migrations.json"
[[ -f "$state" && -L "$home/.config/tmux/tmux.conf" && ! -e "$home/.tmux.conf" ]] || \
  fail 'generic tmux apply did not deploy XDG config and retire the legacy link'
jq -e '
  .profile == "generic" and .packages == ["upstream/tmux","generic/tmux","common/tmux"] and
  (.targets | map(.path) | sort) == ([
    ".config/dotfiles/upstream/tmux/tmux.conf",
    ".config/dotfiles/tmux/generic.conf",
    ".config/dotfiles/tmux/persistence.conf",
    ".config/tmux/tmux.conf"] | sort) and
  .attachments == [] and .backups == []
' "$state" >/dev/null || fail 'generic tmux state inventory is incorrect'
jq -e '
  .migrations == [{id:"tmux-xdg-config-v1",source_fingerprint:.migrations[0].source_fingerprint,
    completed_at:.migrations[0].completed_at,backups:[]}]
' "$ledger" >/dev/null || fail 'tmux XDG migration did not record exactly one no-backup ledger entry'
[[ -f "$REPO_DIR/.tmux.conf" && "$(< "$home/.tmux/plugins/fixture/data")" == 'plugin data' && \
  "$(< "$home/.tmux/resurrect/session")" == 'resurrect data' ]] || \
  fail 'generic apply changed compatibility, plugin, or Resurrect data'
ledger_hash="$(sha256sum "$ledger")"
run_tmux_area "$home" generic apply >/dev/null
[[ "$(sha256sum "$ledger")" == "$ledger_hash" ]] || fail 'generic reapply changed the completed migration ledger'
ln -s "$REPO_DIR/.tmux.conf" "$home/.tmux.conf"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" generic apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'completed tmux migration accepted a reappeared source'
assert_contains "$TEST_OUTPUT" 'already recorded but its retired source reappeared'
rm "$home/.tmux.conf"
run_tmux_area "$home" generic remove >/dev/null
[[ ! -e "$state" && ! -e "$home/.config/tmux/tmux.conf" && -f "$ledger" && \
  -f "$home/.tmux/plugins/fixture/data" && -f "$home/.tmux/resurrect/session" && \
  "$(< "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json")" == 'retained plugin receipt' ]] || \
  fail 'tmux removal did not retain ledger, plugins, and Resurrect data'
pass

# Wrong, broken, and moved legacy links refuse. A concurrent replacement at
# retirement is preserved, and a post-state fault restores link and ledger.
for kind in wrong broken moved; do
  home="$TEST_ROOT/home-legacy-$kind"
  mkdir "$home"
  case "$kind" in
    wrong) ln -s "$REPO_DIR/README.md" "$home/.tmux.conf" ;;
    broken) ln -s "$TEST_ROOT/missing-tmux.conf" "$home/.tmux.conf" ;;
    moved) cp "$REPO_DIR/.tmux.conf" "$TEST_ROOT/moved-tmux.conf"; ln -s "$TEST_ROOT/moved-tmux.conf" "$home/.tmux.conf" ;;
  esac
  set +e
  TEST_OUTPUT="$(run_tmux_area "$home" generic check 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 ]] || fail "$kind legacy tmux link was accepted"
  assert_contains "$TEST_OUTPUT" 'not the exact reviewed legacy tmux link'
done
home="$TEST_ROOT/home-legacy-race"
hold="$TEST_ROOT/legacy-race-hold"
mkdir "$home" "$hold"
ln -s "$REPO_DIR/.tmux.conf" "$home/.tmux.conf"
set +e
( run_tmux_area "$home" generic apply '' before-tmux-legacy-quarantine "$hold" > "$TEST_ROOT/legacy-race.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/legacy-race.rc" ) &
race_pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do [[ -e "$hold/before-tmux-legacy-quarantine.ready" ]] && break; sleep 0.01; done
[[ -e "$hold/before-tmux-legacy-quarantine.ready" ]] || fail 'tmux retirement race did not reach its hold'
rm "$home/.tmux.conf"; ln -s "$REPO_DIR/README.md" "$home/.tmux.conf"
: > "$hold/before-tmux-legacy-quarantine.release"
wait "$race_pid" || true
[[ "$(< "$TEST_ROOT/legacy-race.rc")" != 0 && "$(readlink "$home/.tmux.conf")" == "$REPO_DIR/README.md" ]] || \
  fail 'tmux retirement race clobbered a concurrent link'

home="$TEST_ROOT/home-state-rollback"
mkdir "$home"; ln -s "$REPO_DIR/.tmux.conf" "$home/.tmux.conf"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" generic apply tmux-after-state 2>&1)"; status=$?
set -e
[[ "$status" != 0 && -L "$home/.tmux.conf" && ! -e "$home/.local" && ! -e "$home/.config" ]] || \
  fail 'tmux state-commit fault did not restore migration and deployment state'
pass

# WSL has the exact five-target closure and no fabricated migration when the
# reviewed legacy source is absent.
home="$TEST_ROOT/home-wsl"
mkdir "$home"
run_tmux_area "$home" wsl apply >/dev/null
state="$home/.local/state/dotfiles/v1/tmux.json"
jq -e '
  .profile == "wsl" and .packages == ["upstream/tmux","generic/tmux","wsl/tmux","common/tmux"] and
  (.targets | map(.path) | sort) == ([
    ".config/dotfiles/upstream/tmux/tmux.conf",
    ".config/dotfiles/tmux/generic.conf",
    ".config/dotfiles/tmux/persistence.conf",
    ".config/dotfiles/tmux/wsl.conf",
    ".config/tmux/tmux.conf"] | sort)
' "$state" >/dev/null || fail 'WSL tmux state inventory is incorrect'
[[ ! -e "$home/.local/state/dotfiles/v1/migrations.json" ]] || fail 'WSL apply fabricated a migration without a source'
run_tmux_area "$home" wsl remove >/dev/null
pass

# A fault after legacy retirement restores the exact link and removes every
# uncommitted config, state, and ledger object.
home="$TEST_ROOT/home-migration-rollback"
mkdir "$home"
ln -s "$REPO_DIR/.tmux.conf" "$home/.tmux.conf"
link_value="$(readlink -- "$home/.tmux.conf")"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" generic apply tmux-after-migration 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'injected tmux migration fault unexpectedly succeeded'
assert_contains "$TEST_OUTPUT" "rolled back incomplete deployment of area 'tmux'"
[[ -L "$home/.tmux.conf" && "$(readlink -- "$home/.tmux.conf")" == "$link_value" && \
  ! -e "$home/.config" && ! -e "$home/.local" ]] || fail 'tmux migration rollback was incomplete'
pass

# Native attachment is append-only, records its no-final-newline origin, rolls
# back on fault, and exact removal restores baseline bytes and mode.
home="$TEST_ROOT/home-native-fault"
mkdir -p "$home/.config/tmux"
cp "$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"
chmod 0640 "$home/.config/tmux/tmux.conf"
cp -a "$home" "$TEST_ROOT/native-fault-original"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" omarchy apply tmux-after-attachment 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'injected native attachment fault unexpectedly succeeded'
diff --no-dereference -r "$home" "$TEST_ROOT/native-fault-original" >/dev/null || \
  fail 'native tmux attachment fault did not restore HOME'

home="$TEST_ROOT/home-native"
mkdir -p "$home/.config/tmux" "$home/.tmux/plugins" "$home/.tmux/resurrect"
cp "$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"
truncate -s -1 "$home/.config/tmux/tmux.conf"
chmod 0640 "$home/.config/tmux/tmux.conf"
cp -a "$home/.config/tmux/tmux.conf" "$TEST_ROOT/native-original"
printf 'retained\n' > "$home/.tmux/plugins/data"
printf 'retained\n' > "$home/.tmux/resurrect/data"
run_tmux_area "$home" omarchy apply >/dev/null
state="$home/.local/state/dotfiles/v1/tmux.json"
jq -e '
  .profile == "omarchy" and .packages == ["common/tmux"] and
  (.targets | map(.path)) == [".config/dotfiles/tmux/persistence.conf"] and
  (.attachments | length) == 1 and
  .attachments[0].id == "tmux-native-config-v1.existing-no-final-newline" and
  .attachments[0].path == ".config/tmux/tmux.conf"
' "$state" >/dev/null || fail 'native tmux state did not record exact attachment origin and inventory'
run_tmux_area "$home" omarchy remove >/dev/null
assert_same "$home/.config/tmux/tmux.conf" "$TEST_ROOT/native-original"
[[ "$(stat -c %a -- "$home/.config/tmux/tmux.conf")" == 640 && \
  "$(< "$home/.tmux/plugins/data")" == retained && "$(< "$home/.tmux/resurrect/data")" == retained ]] || \
  fail 'native removal changed baseline mode or retained data'
pass

# Native config must preexist. Refresh may restore only a wholly absent block;
# malformed marker shapes refuse, outside bytes survive, and removal rolls back.
home="$TEST_ROOT/home-native-missing"
mkdir "$home"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" omarchy apply 2>&1)"; status=$?
set -e
[[ "$status" != 0 ]] || fail 'native tmux apply created a missing native config'
assert_contains "$TEST_OUTPUT" 'native Omarchy tmux config is missing'

home="$TEST_ROOT/home-native-refresh"
mkdir -p "$home/.config/tmux"
cp "$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"
run_tmux_area "$home" omarchy apply >/dev/null
cp "$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"
truncate -s -1 "$home/.config/tmux/tmux.conf"
run_tmux_area "$home" omarchy apply >/dev/null
printf '\n# outside after\n' >> "$home/.config/tmux/tmux.conf"
cp -a "$home" "$TEST_ROOT/native-remove-before"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" omarchy remove tmux-remove-after-attachment 2>&1)"; status=$?
set -e
[[ "$status" != 0 ]] || fail 'native tmux removal rollback fault succeeded'
diff --no-dereference -r "$home" "$TEST_ROOT/native-remove-before" >/dev/null || fail 'native tmux removal rollback changed HOME'
run_tmux_area "$home" omarchy remove >/dev/null
expected_native="$(< "$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf")"
[[ "$(< "$home/.config/tmux/tmux.conf")" == "$expected_native"$'\n# outside after' ]] || \
  fail 'native tmux removal did not preserve refreshed outside-block bytes'

home="$TEST_ROOT/home-native-created-origin"; mkdir -p "$home/.config/tmux"
cp "$REPO_DIR/packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf" "$home/.config/tmux/tmux.conf"
run_tmux_area "$home" omarchy apply >/dev/null
state="$home/.local/state/dotfiles/v1/tmux.json"
jq '(.attachments[0].id)="tmux-native-config-v1.created"' "$state" > "$state.new"; mv "$state.new" "$state"
set +e
TEST_OUTPUT="$(run_tmux_area "$home" omarchy remove 2>&1)"; status=$?
set -e
[[ "$status" != 0 ]] || fail 'native tmux accepted attachment origin created'
assert_contains "$TEST_OUTPUT" 'unknown attachment origin'

for shape in partial duplicate nested modified; do
  home="$TEST_ROOT/home-native-malformed-$shape"; mkdir -p "$home/.config/tmux"
  case "$shape" in
    partial) printf '# >>> dotfiles tmux >>>\n' > "$home/.config/tmux/tmux.conf" ;;
    duplicate) printf '%s\n%s\n' '# >>> dotfiles tmux >>>' '# <<< dotfiles tmux <<<' > "$home/.config/tmux/tmux.conf"; printf '%s\n%s\n' '# >>> dotfiles tmux >>>' '# <<< dotfiles tmux <<<' >> "$home/.config/tmux/tmux.conf" ;;
    nested) printf '%s\n%s\n%s\n%s\n' '# >>> dotfiles tmux >>>' '# >>> dotfiles tmux >>>' '# <<< dotfiles tmux <<<' '# <<< dotfiles tmux <<<' > "$home/.config/tmux/tmux.conf" ;;
    modified) printf '%s\nchanged\n%s\n' '# >>> dotfiles tmux >>>' '# <<< dotfiles tmux <<<' > "$home/.config/tmux/tmux.conf" ;;
  esac
  set +e
  TEST_OUTPUT="$(run_tmux_area "$home" omarchy apply 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 ]] || fail "native tmux accepted $shape markers"
  assert_contains "$TEST_OUTPUT" 'partial, malformed, nested, duplicate, or modified'
done
pass

# The isolated runtime interface puts every tmux invocation on one random -L
# socket; no default/current server command is available on this path.
home="$TEST_ROOT/home-isolated"
mkdir "$home"
wrapper="$TEST_ROOT/tmux-wrapper"
cat > "$wrapper" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/isolated-invocations"
exec "$REAL_TMUX" "\$@"
SCRIPT
chmod 0755 "$wrapper"
real_version="$($REAL_TMUX -V)"; real_version="${real_version#tmux }"
HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage7-tmux-test \
  SELECTED_PROFILE=generic MODE=check TMUX_CLIENT_BIN="$wrapper" TMUX_CLIENT_VERSION="$real_version" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/tmux.sh"
    TMUX_CLIENT_BIN="'$wrapper'"
    TMUX_CLIENT_VERSION="'$real_version'"
    validate_tmux_isolated_config checkout
  '
mapfile -t invocations < "$TEST_ROOT/isolated-invocations"
((${#invocations[@]} >= 9)) || fail 'isolated validation did not exercise runtime options and keys'
socket=""
for invocation in "${invocations[@]}"; do
  [[ "$invocation" == -L\ * ]] || fail "isolated validation used a non-explicit socket command: $invocation"
  current="${invocation#-L }"; current="${current%% *}"
  [[ -z "$socket" || "$current" == "$socket" ]] || fail 'isolated validation used more than one socket'
  socket="$current"
done
[[ "$socket" == dotfiles-* ]] || fail 'isolated validation socket name is not unique to the validation run'
pass

# Selected-client compatibility reports both inert options at 3.2a. Active
# server inspection gets PID/version read-only over the socket, uses /proc only
# for identity, and never invokes the mismatched executable.
selected="$TEST_ROOT/selected-tmux"
active="$TEST_ROOT/active-tmux"
cat > "$selected" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/selected-invocations"
if [[ "\${1:-}" == -V ]]; then printf 'tmux 3.2a\n'; exit 0; fi
if [[ "\${1:-}" == -S && "\${2:-}" == "$TEST_ROOT/server-sockets/tmux-$EUID/default" ]]; then printf '4242|3.4\n'; exit 0; fi
exit 1
SCRIPT
cat > "$active" <<SCRIPT
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/active-invocations"
exit 99
SCRIPT
chmod 0755 "$selected" "$active"
mkdir -p "$TEST_ROOT/proc/4242"
ln -s "$active" "$TEST_ROOT/proc/4242/exe"
mkdir -p "$TEST_ROOT/server-sockets/tmux-$EUID"
current_socket="$TEST_ROOT/server-sockets/current"
nc -lU "$current_socket" > /dev/null 2>&1 &
nc_pid=$!
for ((attempt=0; attempt<100; attempt++)); do [[ -S "$current_socket" ]] && break; sleep 0.01; done
[[ -S "$current_socket" ]] || fail 'could not create the unqueryable socket fixture'
home="$TEST_ROOT/home-active"
mkdir "$home"
TEST_OUTPUT="$(HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage7-tmux-test \
  SELECTED_PROFILE=generic MODE=check DOTFILES_TESTING=1 DOTFILES_TEST_TMUX_BIN="$selected" \
  DOTFILES_TEST_TMUX_OWNER=test-owner TMUX_TMPDIR="$TEST_ROOT/server-sockets" TMUX="$current_socket,1,0" \
  DOTFILES_TEST_TMUX_PROC_ROOT="$TEST_ROOT/proc" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"
    source "$DOTFILES_DIR/lib/areas/tmux.sh"
    resolve_tmux_client_owner
    inspect_active_tmux_servers
    report_tmux_active_server_guidance
  ' 2>&1)"
kill "$nc_pid" 2>/dev/null || true
wait "$nc_pid" 2>/dev/null || true
assert_contains "$TEST_OUTPUT" 'inert options: allow-passthrough extended-keys-format'
assert_contains "$TEST_OUTPUT" "default tmux server transition: socket=$TEST_ROOT/server-sockets/tmux-$EUID/default pid=4242 reported-version=3.4"
assert_contains "$TEST_OUTPUT" "current tmux server socket exists but is unqueryable: socket=$current_socket"
assert_contains "$TEST_OUTPUT" 'manually save, exit clients, run tmux kill-server, start the selected tmux owner, then restore'
assert_contains "$(< "$TEST_ROOT/selected-invocations")" "-S $TEST_ROOT/server-sockets/tmux-$EUID/default display-message -p #{pid}|#{version}"
[[ "$(< "$TEST_ROOT/selected-invocations")" != *'kill-server'* && ! -e "$TEST_ROOT/active-invocations" ]] || \
  fail 'active server inspection executed the /proc executable'
pass


# Same-owner servers receive one explicit source-file instruction, never the
# legacy prefix+q advice. Inspection and reporting execute no lifecycle command.
TEST_OUTPUT="$(HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage7-tmux-test bash -c '
  set -Eeuo pipefail
  source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/areas/tmux.sh"
  TMUX_ACTIVE_SERVER_SEEN=true
  TMUX_ACTIVE_SERVER_TRANSITION=false
  TMUX_ACTIVE_SERVER_SAME_OWNER=true
  report_tmux_active_server_guidance
' 2>&1)"
assert_contains "$TEST_OUTPUT" 'run tmux source-file ~/.config/tmux/tmux.conf once'
[[ "$TEST_OUTPUT" != *'prefix + q'* && "$TEST_OUTPUT" != *'Configuration reloaded'* ]] || \
  fail 'same-owner guidance retained the legacy reload instruction or executed reload output'
pass

# A test server that still answers after kill is not orphaned behind deleted
# state: cleanup retains and reports its explicit recovery root.
recovery="$TEST_ROOT/retained-validation"
set +e
TEST_OUTPUT="$(HOME="$TEST_ROOT/home-isolated" TARGET_ROOT="$TEST_ROOT/home-isolated" DOTFILES_DIR="$REPO_DIR" \
  SCRIPT_NAME=stage7-tmux-test RECOVERY="$recovery" bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/areas/tmux.sh"
    mkdir "$RECOVERY"; track_temp_path "$RECOVERY"
    TMUX_ISOLATED_BIN=/bin/true; TMUX_ISOLATED_SOCKET=fixture; TMUX_ISOLATED_TMPDIR="$RECOVERY"
    TMUX_ISOLATED_SANDBOX="$RECOVERY"; TMUX_VALIDATION_HOME="$RECOVERY"
    tmux_isolated_exec() { return 0; }
    ! tmux_stop_isolated_validation
    array_contains "$RECOVERY" "${RETAINED_TEMP_PATHS[@]}"
  ' 2>&1)"; status=$?
set -e
[[ "$status" == 0 && -d "$recovery" ]] || fail 'failed isolated-server cleanup did not retain its recovery root'
assert_contains "$TEST_OUTPUT" "retained recovery root: $recovery"
rm -rf "$recovery"
pass

# Production validation fails closed before parser startup when a denied-network
# namespace cannot be established.
mkdir "$TEST_ROOT/no-unshare-bin"
cat > "$TEST_ROOT/no-unshare-bin/unshare" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
chmod 0755 "$TEST_ROOT/no-unshare-bin/unshare"
home="$TEST_ROOT/home-no-network"; mkdir "$home"
set +e
TEST_OUTPUT="$(HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage7-tmux-test \
  PATH="$TEST_ROOT/no-unshare-bin:/usr/bin:/bin" SELECTED_PROFILE=generic MODE=check bash -c '
    set -Eeuo pipefail
    source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/provisioning.sh"; source "$DOTFILES_DIR/lib/areas/tmux.sh"
    TMUX_CLIENT_BIN=/usr/bin/tmux; TMUX_CLIENT_VERSION=3.4
    validate_tmux_isolated_config checkout
  ' 2>&1)"; status=$?
set -e
[[ "$status" != 0 ]] || fail 'tmux validation ran without a denied-network namespace'
assert_contains "$TEST_OUTPUT" 'could not establish a denied-network namespace'
pass

# Inventory validation fails closed on an extra package target, and production
# readiness remains unchanged.
set +e
TEST_OUTPUT="$(HOME="$TEST_ROOT/home-inventory" TARGET_ROOT="$TEST_ROOT/home-inventory" DOTFILES_DIR="$REPO_DIR" \
  SCRIPT_NAME=stage7-tmux-test SELECTED_PROFILE=generic bash -c '
    set -Eeuo pipefail
    mkdir -p "$HOME"
    source "$DOTFILES_DIR/lib/common.sh"
    source "$DOTFILES_DIR/lib/engine.sh"
    source "$DOTFILES_DIR/lib/areas/tmux.sh"
    TARGET_PATHS=(
      .config/dotfiles/upstream/tmux/tmux.conf
      .config/dotfiles/tmux/generic.conf
      .config/dotfiles/tmux/persistence.conf
      .config/tmux/tmux.conf
      .config/tmux/unexpected.conf)
    validate_tmux_target_inventory
  ' 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'tmux target inventory accepted an unexpected target'
assert_contains "$TEST_OUTPUT" 'tmux package closure contains unexpected target'
grep -qxF 'area|tmux|ready' "$REPO_DIR/manifests/areas.tsv" || fail 'Stage 7 tmux readiness gate did not close'
mapfile -t plugin_order < <(jq -r '.plugins[].id' "$REPO_DIR/manifests/tmux-plugins.lock.json")
[[ "${plugin_order[*]}" == 'tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum' ]] || \
  fail 'tmux plugin lock order is not exact'
jq -e '[.plugins[].loading] == ["tpm","tpm","managed-hooks","tpm"] and
  [.plugins[] | select(.loading == "tpm") | .id] == ["tpm","tmux-resurrect","tmux-continuum"] and
  (.plugins[] | select(.id == "tmux-assistant-resurrect") | .hooks) == {
    "@resurrect-hook-post-save-all":"scripts/save-assistant-sessions.sh",
    "@resurrect-hook-post-restore-all":"scripts/restore-assistant-sessions.sh"}' \
  "$REPO_DIR/manifests/tmux-plugins.lock.json" >/dev/null || fail 'tmux loading model is not exact'
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" || "$line" == \#* ]] || fail 'WSL tmux adapter contains a command'
done < "$REPO_DIR/packages/wsl/tmux/.config/dotfiles/tmux/wsl.conf"
bad_wsl_repo="$TEST_ROOT/bad-wsl-repo"
mkdir -p "$bad_wsl_repo/packages/wsl/tmux/.config/dotfiles/tmux"
printf 'set -g mouse off\n' > "$bad_wsl_repo/packages/wsl/tmux/.config/dotfiles/tmux/wsl.conf"
set +e
TEST_OUTPUT="$(HOME="$TEST_ROOT/home-inventory" TARGET_ROOT="$TEST_ROOT/home-inventory" DOTFILES_DIR="$bad_wsl_repo" \
  SCRIPT_NAME=stage7-tmux-test bash -c '
    set -Eeuo pipefail
    source "'$REPO_DIR'/lib/common.sh"; source "'$REPO_DIR'/lib/engine.sh"; source "'$REPO_DIR'/lib/areas/tmux.sh"
    validate_tmux_wsl_adapter
  ' 2>&1)"; status=$?
set -e
[[ "$status" != 0 ]] || fail 'WSL tmux adapter command enforcement accepted a command'
assert_contains "$TEST_OUTPUT" 'must contain no commands'
pass

printf 'PASS: %d Stage 7 tmux lifecycle test groups\n' "$TEST_COUNT"
