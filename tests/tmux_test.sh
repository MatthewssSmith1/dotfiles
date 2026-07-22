#!/usr/bin/env bash
# tmux domain tests: area lifecycle, plugin provisioning and bootstrap gating,
# and the scripts/tmux-parser-fixtures tool.

set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly REAL_TMUX=/usr/bin/tmux
readonly FIXTURES="$REPO_DIR/scripts/tmux-parser-fixtures"

# =============================================================================
# Section 1: tmux area lifecycle (from stage7_tmux_test.sh)
# =============================================================================

[[ -f "$REAL_TMUX" && ! -L "$REAL_TMUX" && -x "$REAL_TMUX" && "$($REAL_TMUX -V)" == 'tmux 3.4' ]] || \
  fail 'tmux lifecycle tests require the explicit distro /usr/bin/tmux 3.4 parser'

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

# =============================================================================
# Section 2: TPM/resurrect/continuum plugin provisioning and bootstrap gating
# (from stage7_tmux_provisioning_test.sh)
# =============================================================================

fixture="$(copy_repo_fixture tmux-plugins)"
repos="$TEST_ROOT/repos"
mkdir "$repos"
set_area_status "$fixture" nvim framework

git_fixture_config() {
  /usr/bin/git -C "$1" config user.name 'Stage Seven Fixture'
  /usr/bin/git -C "$1" config user.email stage7@example.invalid
}

child="$repos/tpm-test-child"
/usr/bin/git init -q "$child"
git_fixture_config "$child"
printf 'submodule fixture\n' > "$child/content"
/usr/bin/git -C "$child" add content
/usr/bin/git -C "$child" commit -qm child

declare -A OLD_COMMITS=() LOCK_COMMITS=()
for id in tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum; do
  source_repo="$repos/$id"
  /usr/bin/git init -q "$source_repo"
  git_fixture_config "$source_repo"
  printf 'old %s\n' "$id" > "$source_repo/content"
  /usr/bin/git -C "$source_repo" add content
  /usr/bin/git -C "$source_repo" commit -qm old
  OLD_COMMITS["$id"]="$(/usr/bin/git -C "$source_repo" rev-parse HEAD)"
  if [[ "$id" == tpm ]]; then
    /usr/bin/git -C "$source_repo" -c protocol.file.allow=always submodule add -q "$child" test/fixture
    cat > "$source_repo/tpm" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'tpm\n' >> "$TMUX_INIT_LOG"
"$HOME/.tmux/plugins/tmux-resurrect/resurrect.tmux"
"$HOME/.tmux/plugins/tmux-continuum/continuum.tmux"
SCRIPT
    chmod 0755 "$source_repo/tpm"
  else
    printf 'locked %s\n' "$id" > "$source_repo/content"
    case "$id" in
      tmux-resurrect) entry=resurrect.tmux ;;
      tmux-assistant-resurrect) entry=tmux-assistant-resurrect.tmux ;;
      tmux-continuum) entry=continuum.tmux ;;
    esac
    cat > "$source_repo/$entry" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\\n' '$id' >> "\$TMUX_INIT_LOG"
SCRIPT
    chmod 0755 "$source_repo/$entry"
    if [[ "$id" == tmux-assistant-resurrect ]]; then
      cat > "$source_repo/$entry" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'assistant-entrypoint-executed\n' >> "$ASSISTANT_ENTRYPOINT_SENTINEL"
mkdir -p "$HOME/.claude" "$HOME/.config/opencode/plugins"
printf '{"mutated":true}\n' > "$HOME/.claude/settings.json"
ln -sf "$0" "$HOME/.config/opencode/plugins/session-tracker.js"
SCRIPT
      mkdir "$source_repo/scripts"
      cat > "$source_repo/scripts/save-assistant-sessions.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'save-assistant-sessions\n' >> "$ASSISTANT_HOOK_LOG"
SCRIPT
      cat > "$source_repo/scripts/restore-assistant-sessions.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'restore-assistant-sessions\n' >> "$ASSISTANT_HOOK_LOG"
SCRIPT
      chmod 0755 "$source_repo/$entry" "$source_repo/scripts/save-assistant-sessions.sh" \
        "$source_repo/scripts/restore-assistant-sessions.sh"
    fi
  fi
  /usr/bin/git -C "$source_repo" add -A
  /usr/bin/git -C "$source_repo" commit -qm locked
  LOCK_COMMITS["$id"]="$(/usr/bin/git -C "$source_repo" rev-parse HEAD)"
  jq --arg id "$id" --arg commit "${LOCK_COMMITS[$id]}" \
    '(.plugins[] | select(.id == $id) | .commit)=$commit' \
    "$fixture/manifests/tmux-plugins.lock.json" > "$fixture/manifests/tmux-plugins.lock.json.new"
  mv "$fixture/manifests/tmux-plugins.lock.json.new" "$fixture/manifests/tmux-plugins.lock.json"
done

fetch_seam="$TEST_ROOT/fetch-seam"
cat > "$fetch_seam" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
repository="$1"; commit="$2"; stage="$3"
base="${repository##*/}"
printf 'NETWORK fetch-exact-depth-1 %s %s\n' "$base" "$commit"
printf '%s\n' "$base" >> "$NETWORK_LOG"
/usr/bin/git clone -q --no-checkout --no-tags --no-recurse-submodules "$FIXTURE_REPOS/$base" "$stage"
/usr/bin/git -C "$stage" checkout -q --detach "$commit"
/usr/bin/git -C "$stage" remote set-url origin "$repository"
SCRIPT
chmod 0755 "$fetch_seam"
network_log="$TEST_ROOT/network.log"
: > "$network_log"

install_checkout() {
  local home="$1" id="$2" commit="$3" directory repository
  directory="$(jq -r --arg id "$id" '.plugins[] | select(.id == $id) | .directory' "$fixture/manifests/tmux-plugins.lock.json")"
  repository="$(jq -r --arg id "$id" '.plugins[] | select(.id == $id) | .repository' "$fixture/manifests/tmux-plugins.lock.json")"
  mkdir -p "$home/.tmux/plugins"
  /usr/bin/git clone -q --no-checkout --no-tags --no-recurse-submodules "$repos/$id" "$home/.tmux/plugins/$directory"
  /usr/bin/git -C "$home/.tmux/plugins/$directory" checkout -q --detach "$commit"
  /usr/bin/git -C "$home/.tmux/plugins/$directory" remote set-url origin "$repository"
}

install_all_checkouts() {
  local home="$1" selected_id="${2:-}" selected_commit="${3:-}" id commit
  for id in tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum; do
    commit="${LOCK_COMMITS[$id]}"
    [[ "$id" != "$selected_id" ]] || commit="$selected_commit"
    install_checkout "$home" "$id" "$commit"
  done
}

invoke_plugin() {
  local home="$1" operation="$2" fail_at="${3:-}" hold_at="${4:-}" hold_dir="${5:-}"
  HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$fixture" SCRIPT_NAME=stage7-plugin-test \
    DOTFILES_TESTING=1 DOTFILES_TEST_TMUX_FETCH="$fetch_seam" DOTFILES_TEST_FAIL_AT="$fail_at" \
    DOTFILES_TEST_HOLD_AT="$hold_at" DOTFILES_TEST_HOLD_DIR="$hold_dir" \
    FIXTURE_REPOS="$repos" NETWORK_LOG="$network_log" bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/engine.sh"
      source "$DOTFILES_DIR/lib/provisioning.sh"
      source "$DOTFILES_DIR/lib/areas/tmux.sh"
      AREA_ORDER=(git bash tmux nvim zsh)
      AREA_STATUS=([git]=ready [bash]=ready [tmux]=framework [nvim]=framework [zsh]=ready)
      plan_status=0
      tmux_preflight_plugin_provision_plan || plan_status=1
      print_tmux_plugin_provisioning_plan
      ((plan_status == 0)) || exit 1
      case "$1" in
        apply) tmux_apply_plugin_provisioning ;;
        check) [[ "$TMUX_PLUGIN_PLAN_PENDING" == false ]] ;;
        exact) tmux_validate_exact_plugin_closure ;;
        plan) : ;;
      esac
    ' _ "$operation"
}

capture_plugin() {
  set +e
  TEST_OUTPUT="$(invoke_plugin "$@" 2>&1)"
  TEST_RC=$?
  set -e
}

assert_no_transaction_debris() {
  local home="$1" debris
  debris="$(/usr/bin/find "$home" \( -name '*.dotfiles-stage.*' -o -name '*.dotfiles-quarantine.*' \) -print -quit)"
  [[ -z "$debris" ]] || fail "transaction debris remains: $debris"
}

plugin_index_inventory() {
  local home="$1" id index
  for id in tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum; do
    index="$home/.tmux/plugins/$id/.git/index"
    printf '%s|%s|%s\n' "$id" "$(stat -c '%d:%i:%u:%a:%s:%y' -- "$index")" "$(sha256sum "$index")"
  done
}

# Exact unreceipted checkouts are adopted only by explicit provisioning. The
# receipt is ordered, mode 0600, and TPM's gitlink remains uninitialized.
home="$(new_home adopt)"
install_all_checkouts "$home"
: > "$network_log"
capture_plugin "$home" plan
((TEST_RC == 0)) || fail 'adoption plan failed'
assert_contains "$TEST_OUTPUT" 'tpm: action=adopt network=none'
capture_plugin "$home" exact
((TEST_RC != 0)) || fail 'ordinary exact validation adopted unreceipted checkouts'
capture_plugin "$home" apply
((TEST_RC == 0)) || fail 'explicit adoption failed'
[[ ! -s "$network_log" ]] || fail 'adoption invoked the fetch seam'
receipt="$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
[[ -f "$receipt" && "$(stat -c %a -- "$receipt")" == 600 ]] || fail 'adoption receipt is missing or has the wrong mode'
jq -e --arg hash "$(sha256sum "$fixture/manifests/tmux-plugins.lock.json" | cut -d' ' -f1)" '
  .schema_version == 1 and .lock_sha256 == $hash and
  (.plugins | map(.id)) == ["tpm","tmux-resurrect","tmux-assistant-resurrect","tmux-continuum"] and
  all(.plugins[]; (.tree | test("^[0-9a-f]{40}$")))
' "$receipt" >/dev/null || fail 'adoption receipt content is not the exact ordered lock closure'
[[ -d "$home/.tmux/plugins/tpm/test/fixture" && -z "$(/usr/bin/find "$home/.tmux/plugins/tpm/test/fixture" -mindepth 1 -print -quit)" ]] || \
  fail 'TPM test submodule was initialized during adoption'
capture_plugin "$home" exact
((TEST_RC == 0)) || fail 'receipted adopted closure was not exact'
index_before="$(plugin_index_inventory "$home")"
capture_plugin "$home" exact
((TEST_RC == 0)) || fail 'repeated exact validation failed'
[[ "$index_before" == "$(plugin_index_inventory "$home")" ]] || \
  fail 'read-only exact validation changed plugin index identity, content, mode, size, or mtime'
receipt_identity="$(stat -c '%d:%i:%y' -- "$receipt"):$(sha256sum "$receipt")"
capture_plugin "$home" apply
((TEST_RC == 0)) || fail 'converged explicit provisioning failed'
[[ "$receipt_identity" == "$(stat -c '%d:%i:%y' -- "$receipt"):$(sha256sum "$receipt")" ]] || \
  fail 'converged explicit provisioning rewrote its receipt'
pass

# Exactly the reviewed malformed HTTPS origin for the same locked owner/repo is
# normalized only by explicit provisioning, using staged canonical replacement.
home="$(new_home reviewed-origin)"
install_all_checkouts "$home"
capture_plugin "$home" apply
((TEST_RC == 0)) || fail 'reviewed-origin fixture adoption failed'
for id in tpm tmux-resurrect tmux-assistant-resurrect; do
  repository="$(jq -r --arg id "$id" '.plugins[] | select(.id == $id) | .repository' "$fixture/manifests/tmux-plugins.lock.json")"
  legacy_repository="${repository/https:\/\/github.com\//https:\/\/git::@github.com\/}"
  /usr/bin/git -C "$home/.tmux/plugins/$id" remote set-url origin "$legacy_repository"
done
capture_plugin "$home" exact
((TEST_RC != 0)) || fail 'ordinary exact validation accepted a reviewed legacy origin'
assert_contains "$TEST_OUTPUT" 'unknown, noncanonical, or ambiguous origin metadata'
old_tpm_identity="$(stat -c '%d:%i' -- "$home/.tmux/plugins/tpm")"
: > "$network_log"
capture_plugin "$home" plan
((TEST_RC == 0)) || fail 'explicit provisioning did not classify reviewed legacy origins'
for id in tpm tmux-resurrect tmux-assistant-resurrect; do
  assert_contains "$TEST_OUTPUT" "$id: action=normalize-origin network=fetch-exact-depth-1"
done
assert_contains "$TEST_OUTPUT" 'reviewed legacy https://git::@github.com origin requires staged canonical replacement'
capture_plugin "$home" apply
((TEST_RC == 0)) || fail 'reviewed legacy origin normalization failed'
[[ "$old_tpm_identity" != "$(stat -c '%d:%i' -- "$home/.tmux/plugins/tpm")" ]] || \
  fail 'reviewed legacy origin was mutated in place instead of replaced from staging'
for id in tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum; do
  repository="$(jq -r --arg id "$id" '.plugins[] | select(.id == $id) | .repository' "$fixture/manifests/tmux-plugins.lock.json")"
  [[ "$(/usr/bin/git -C "$home/.tmux/plugins/$id" remote get-url origin)" == "$repository" ]] || \
    fail "origin normalization did not install canonical metadata for $id"
done
[[ "$(wc -l < "$network_log")" == 3 ]] || fail 'origin normalization did not stage exactly the three reviewed replacements'
capture_plugin "$home" exact
((TEST_RC == 0)) || fail 'normalized reviewed origins did not converge exactly'
pass

# Missing checkouts stage from the exact HTTPS lock identities. Every plan line
# is emitted before the first exact-fetch seam invocation.
home="$(new_home install)"
: > "$network_log"
capture_plugin "$home" apply
((TEST_RC == 0)) || fail 'missing plugin installation failed'
plan_prefix="${TEST_OUTPUT%%NETWORK fetch-exact-depth-1*}"
for id in tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum; do
  assert_contains "$plan_prefix" "$id: action=install network=fetch-exact-depth-1"
done
[[ "$(wc -l < "$network_log")" == 4 ]] || fail 'installation did not stage every locked plugin exactly once'
capture_plugin "$home" check
((TEST_RC == 0)) || fail 'installed closure did not converge'
[[ "$TEST_OUTPUT" == *'action=exact network=none'* ]] || fail 'converged plan did not classify exact checkouts'
assert_no_transaction_debris "$home"
pass

# An exact receipted fixture closure initializes only TPM, Resurrect, and
# Continuum. Assistant Resurrect remains functional through the two managed
# hooks, while its mutating TPM entrypoint is never executed.
capture_plugin "$home" exact
((TEST_RC == 0)) || fail 'offline startup fixture did not pass real exact-closure validation'
cp -a "$home/.tmux/plugins" "$TEST_ROOT/plugins-before-offline-startup"
receipt_before_startup="$(sha256sum "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json")"
deny_bin="$TEST_ROOT/offline-startup-deny-bin"
mkdir "$deny_bin"
for command_name in git curl wget ssh scp mkdir ln mv mktemp jq; do
  cat > "$deny_bin/$command_name" <<'SCRIPT'
#!/usr/bin/env bash
case "${0##*/}" in
  git|curl|wget|ssh|scp) sentinel="$NETWORK_SENTINEL" ;;
  *) sentinel="$WRITE_SENTINEL" ;;
esac
printf '%s\n' "${0##*/} $*" >> "$sentinel"
exit 97
SCRIPT
  chmod 0755 "$deny_bin/$command_name"
done
startup_config="$TEST_ROOT/offline-plugin-startup.conf"
printf 'source-file "%s"\n' "$fixture/packages/common/tmux/.config/dotfiles/tmux/persistence.conf" > "$startup_config"
startup_socket_root="$TEST_ROOT/offline-plugin-socket"
mkdir "$startup_socket_root"
startup_log="$TEST_ROOT/offline-plugin-init.log"
network_sentinel="$TEST_ROOT/offline-plugin-network.log"
write_sentinel="$TEST_ROOT/offline-plugin-write.log"
assistant_entrypoint_sentinel="$TEST_ROOT/assistant-entrypoint.log"
assistant_hook_log="$TEST_ROOT/assistant-hook.log"
mkdir -p "$home/.claude" "$home/.config/opencode"
printf '{"preserved":true}\n' > "$home/.claude/settings.json"
printf '{"preserved":true}\n' > "$home/.config/opencode/opencode.json"
claude_before="$(sha256sum "$home/.claude/settings.json")"
opencode_before="$(sha256sum "$home/.config/opencode/opencode.json")"
set +e
TEST_OUTPUT="$(unshare --user --map-root-user --net env -u TMUX HOME="$home" PATH="$deny_bin:/usr/bin:/bin" \
  TMUX_TMPDIR="$startup_socket_root" TMUX_INIT_LOG="$startup_log" NETWORK_SENTINEL="$network_sentinel" \
  WRITE_SENTINEL="$write_sentinel" ASSISTANT_ENTRYPOINT_SENTINEL="$assistant_entrypoint_sentinel" \
  ASSISTANT_HOOK_LOG="$assistant_hook_log" STARTUP_CONFIG="$startup_config" \
  SAVE_HOOK="$TEST_ROOT/save-hook" RESTORE_HOOK="$TEST_ROOT/restore-hook" /usr/bin/bash -c '
    set -Eeuo pipefail
    /usr/bin/tmux -L stage7-offline -f "$STARTUP_CONFIG" new-session -d -s fixture
    for ((attempt=0; attempt<200; attempt++)); do
      [[ -f "$TMUX_INIT_LOG" && "$(wc -l < "$TMUX_INIT_LOG")" == 3 ]] && break
      sleep 0.01
    done
    [[ -f "$TMUX_INIT_LOG" && "$(wc -l < "$TMUX_INIT_LOG")" == 3 ]]
    /usr/bin/tmux -L stage7-offline show-options -gv @resurrect-hook-post-save-all > "$SAVE_HOOK"
    /usr/bin/tmux -L stage7-offline show-options -gv @resurrect-hook-post-restore-all > "$RESTORE_HOOK"
    /usr/bin/tmux -L stage7-offline kill-server
  ' 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 0)) || fail 'denied-network exact plugin startup failed'
[[ "$(< "$startup_log")" == $'tpm\ntmux-resurrect\ntmux-continuum' ]] || \
  fail 'plugin startup did not execute only the exact TPM-loaded paths'
[[ ! -e "$network_sentinel" ]] || fail 'offline plugin startup invoked a network or Git sentinel'
[[ ! -e "$write_sentinel" && ! -e "$assistant_entrypoint_sentinel" ]] || \
  fail 'offline plugin startup executed the assistant entrypoint or a denied HOME-write sentinel'
[[ "$claude_before" == "$(sha256sum "$home/.claude/settings.json")" &&
  "$opencode_before" == "$(sha256sum "$home/.config/opencode/opencode.json")" &&
  ! -e "$home/.config/opencode/plugins" ]] || fail 'offline startup changed Claude or OpenCode state'
[[ "$(< "$TEST_ROOT/save-hook")" == "bash \"$home/.tmux/plugins/tmux-assistant-resurrect/scripts/save-assistant-sessions.sh\"" &&
  "$(< "$TEST_ROOT/restore-hook")" == "bash \"$home/.tmux/plugins/tmux-assistant-resurrect/scripts/restore-assistant-sessions.sh\"" ]] || \
  fail 'managed Assistant Resurrect options do not point to the locked hook scripts'
HOME="$home" ASSISTANT_HOOK_LOG="$assistant_hook_log" /usr/bin/bash -c "$(< "$TEST_ROOT/save-hook")"
HOME="$home" ASSISTANT_HOOK_LOG="$assistant_hook_log" /usr/bin/bash -c "$(< "$TEST_ROOT/restore-hook")"
[[ "$(< "$assistant_hook_log")" == $'save-assistant-sessions\nrestore-assistant-sessions' ]] || \
  fail 'managed Assistant Resurrect save/restore hooks are not functional'
diff --no-dereference -r "$TEST_ROOT/plugins-before-offline-startup" "$home/.tmux/plugins" >/dev/null || \
  fail 'offline plugin startup mutated a locked checkout'
[[ "$receipt_before_startup" == "$(sha256sum "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json")" ]] || \
  fail 'offline plugin startup changed its exact receipt'
capture_plugin "$home" exact
((TEST_RC == 0)) || fail 'offline startup changed the exact receipted closure'
pass

# Clean canonical commit drift is replaceable, while a pre-receipt fault
# restores the old checkout and leaves no receipt or transaction debris.
home="$(new_home replace-rollback)"
install_all_checkouts "$home" tpm "${OLD_COMMITS[tpm]}"
: > "$network_log"
capture_plugin "$home" apply tmux-plugin-before-receipt
((TEST_RC != 0 && TEST_RC != 70)) || fail 'pre-receipt replacement fault had the wrong status'
[[ "$(/usr/bin/git -C "$home/.tmux/plugins/tpm" rev-parse HEAD)" == "${OLD_COMMITS[tpm]}" ]] || \
  fail 'replacement rollback did not restore the old plugin'
[[ ! -e "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json" ]] || fail 'pre-receipt fault committed a receipt'
assert_no_transaction_debris "$home"
capture_plugin "$home" apply
((TEST_RC == 0)) || fail 'clean canonical replacement failed'
[[ "$(/usr/bin/git -C "$home/.tmux/plugins/tpm" rev-parse HEAD)" == "${LOCK_COMMITS[tpm]}" ]] || \
  fail 'replacement did not install the locked commit'
pass

# Staging, quarantine, and install faults all roll back. A fault after the
# receipt commit retains the exact new closure and removes old quarantines.
for point in tmux-plugin-after-staging tmux-plugin-after-quarantine tmux-plugin-after-install; do
  home="$(new_home "fault-${point##*-}")"
  install_all_checkouts "$home" tpm "${OLD_COMMITS[tpm]}"
  capture_plugin "$home" apply "$point"
  ((TEST_RC != 0 && TEST_RC != 70)) || fail "$point had the wrong status"
  [[ "$(/usr/bin/git -C "$home/.tmux/plugins/tpm" rev-parse HEAD)" == "${OLD_COMMITS[tpm]}" ]] || \
    fail "$point did not restore the old checkout"
  [[ ! -e "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json" ]] || fail "$point committed a receipt"
  assert_no_transaction_debris "$home"
done
home="$(new_home after-receipt)"
install_all_checkouts "$home" tpm "${OLD_COMMITS[tpm]}"
capture_plugin "$home" apply tmux-plugin-after-receipt
((TEST_RC != 0 && TEST_RC != 70)) || fail 'after-receipt fault had the wrong status'
invoke_plugin "$home" exact >/dev/null || fail 'after-receipt fault did not retain the committed exact closure'
assert_no_transaction_debris "$home"
pass

# Unknown or ambiguous origin, dirty state, linked topology, symlinks, and
# unexpected root entries refuse before staging or managed mutation.
home="$(new_home refusals)"
install_all_checkouts "$home"
/usr/bin/git -C "$home/.tmux/plugins/tpm" remote set-url origin https://github.com/evil/tpm
: > "$network_log"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'unknown origin was accepted'
assert_contains "$TEST_OUTPUT" 'unknown, noncanonical, or ambiguous origin metadata'
assert_contains "$TEST_OUTPUT" 'tmux-continuum: action=adopt network=none'
[[ ! -s "$network_log" ]] || fail 'origin refusal staged a clone'
/usr/bin/git -C "$home/.tmux/plugins/tpm" remote set-url origin https://github.com/tmux-plugins/tpm
printf 'dirty\n' >> "$home/.tmux/plugins/tpm/content"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'dirty checkout was accepted'
assert_contains "$TEST_OUTPUT" 'dirty, including untracked files or submodule drift'
rm -rf -- "$home"
home="$(new_home ambiguous)"
install_all_checkouts "$home"
/usr/bin/git -C "$home/.tmux/plugins/tpm" remote add extra https://github.com/tmux-plugins/tpm
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'additional remote was accepted'
assert_contains "$TEST_OUTPUT" 'origin as its only remote'
rm -rf -- "$home/.tmux/plugins/tpm"
ln -s "$repos/tpm" "$home/.tmux/plugins/tpm"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'symlinked checkout was accepted'
rm -- "$home/.tmux/plugins/tpm"
printf 'unexpected\n' > "$home/.tmux/plugins/unexpected"
  capture_plugin "$home" plan
  ((TEST_RC != 0)) || fail 'unexpected root entry was accepted'
  assert_contains "$TEST_OUTPUT" 'unexpected tmux plugin closure entry'
  for id in tpm tmux-resurrect tmux-assistant-resurrect tmux-continuum; do
    assert_contains "$TEST_OUTPUT" "$id: action=refuse network=none"
  done
  [[ "$TEST_OUTPUT" != *'action=install'* && "$TEST_OUTPUT" != *'action=adopt'* ]] || \
    fail 'root closure refusal left a plugin pending for provisioning'
home="$(new_home linked)"
mkdir -p "$home/.tmux/plugins"
/usr/bin/git -C "$repos/tpm" worktree add -q --detach "$home/.tmux/plugins/tpm" "${LOCK_COMMITS[tpm]}"
for id in tmux-resurrect tmux-assistant-resurrect tmux-continuum; do install_checkout "$home" "$id" "${LOCK_COMMITS[$id]}"; done
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'linked worktree was accepted'
assert_contains "$TEST_OUTPUT" 'ordinary non-symlinked checkout'
pass

# Corrupt active receipt metadata and trees refuse; explicit provisioning does
# not reinterpret an active corrupt receipt as adoptable state.
home="$TEST_ROOT/home-install"
cp "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json" "$TEST_ROOT/good-receipt"
jq '(.plugins[0].tree)="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$TEST_ROOT/good-receipt" > \
  "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'corrupt active receipt tree was accepted'
assert_contains "$TEST_OUTPUT" 'receipt tree is corrupt'
printf '{broken\n' > "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'malformed receipt was accepted'
assert_contains "$TEST_OUTPUT" 'malformed or newer tmux plugin receipt'
cp "$TEST_ROOT/good-receipt" "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"

# Unknown stale lock identities are never downgraded to adoption without a
# reviewed lock-history catalog.
jq '.lock_sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$TEST_ROOT/good-receipt" > "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
chmod 0600 "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'unknown stale tmux receipt hash was accepted'
assert_contains "$TEST_OUTPUT" 'receipt lock identity is not the active known lock'
[[ "$TEST_OUTPUT" != *'action=adopt'* ]] || fail 'unknown stale receipt was downgraded to adoption'
cp "$TEST_ROOT/good-receipt" "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"

chmod 0644 "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'unsafe tmux receipt mode was accepted'
assert_contains "$TEST_OUTPUT" 'tmux plugin receipt has an unsafe mode'
chmod 0600 "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"

jq '(.plugins[0].directory)="."' "$TEST_ROOT/good-receipt" > \
  "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
chmod 0600 "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail "tmux receipt directory '.' was accepted"
assert_contains "$TEST_OUTPUT" 'malformed or newer tmux plugin receipt'
cp "$TEST_ROOT/good-receipt" "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
pass

# Directory dot components and declaration text that merely contains a locked
# substring are not valid lock/persistence identities.
cp "$fixture/manifests/tmux-plugins.lock.json" "$TEST_ROOT/good-plugin-lock"
jq '(.plugins[0].directory)="."' "$TEST_ROOT/good-plugin-lock" > "$fixture/manifests/tmux-plugins.lock.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail "tmux plugin directory '.' was accepted"
assert_contains "$TEST_OUTPUT" 'malformed or unknown tmux plugin lock'
jq '(.plugins[0].directory)=".."' "$TEST_ROOT/good-plugin-lock" > "$fixture/manifests/tmux-plugins.lock.json"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail "tmux plugin directory '..' was accepted"
cp "$TEST_ROOT/good-plugin-lock" "$fixture/manifests/tmux-plugins.lock.json"
jq -e '.properties.plugins.items.oneOf == [{"$ref":"#/$defs/tpmPlugin"},{"$ref":"#/$defs/managedHooksPlugin"}] and
  .["$defs"].pluginBase.properties.directory.not.enum == [".",".."]' \
  "$fixture/schemas/tmux-plugin-lock-v1.schema.json" >/dev/null || fail 'lock schema does not reject dot directories'
jq -e '.["$defs"].plugin.properties.directory.not.enum == [".",".."]' \
  "$fixture/schemas/tmux-plugin-receipt-v1.schema.json" >/dev/null || fail 'receipt schema does not reject dot directories'

persistence="$fixture/packages/common/tmux/.config/dotfiles/tmux/persistence.conf"
cp "$persistence" "$TEST_ROOT/good-persistence"
sed -i "s|set -g @plugin 'tmux-plugins/tpm'|set -g @plugin 'evil/tpm' # set -g @plugin 'tmux-plugins/tpm'|" "$persistence"
capture_plugin "$home" plan
((TEST_RC != 0)) || fail 'plugin declaration substring bypass was accepted'
assert_contains "$TEST_OUTPUT" 'malformed tmux persistence plugin declaration'
cp "$TEST_ROOT/good-persistence" "$persistence"
pass

# A concurrent edit to a transaction-installed checkout is preserved. Because
# the old closure cannot be restored without clobbering it, status 70 survives.
home="$(new_home concurrent)"
hold="$TEST_ROOT/hold"
mkdir "$hold"
set +e
( invoke_plugin "$home" apply tmux-plugin-after-install tmux-plugin-after-install "$hold" > "$TEST_ROOT/concurrent.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/concurrent.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/tmux-plugin-after-install.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/tmux-plugin-after-install.ready" ]] || fail 'concurrent test did not reach the install hold'
printf 'concurrent\n' >> "$home/.tmux/plugins/tpm/content"
: > "$hold/tmux-plugin-after-install.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/concurrent.rc")" == 70 ]] || fail 'plugin rollback failure did not preserve status 70'
[[ "$(tail -n 1 "$home/.tmux/plugins/tpm/content")" == concurrent ]] || fail 'rollback clobbered a concurrent plugin edit'
[[ ! -e "$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json" ]] || fail 'concurrent rollback failure committed a receipt'
assert_contains "$(< "$TEST_ROOT/concurrent.out")" "$home/.tmux/plugins/tpm"
pass

# Receipt commit is not declared complete until exact bytes, owner, mode, and
# stable post-identity verify. A same-UID test race is retained and forces 70.
home="$(new_home receipt-race)"
hold="$TEST_ROOT/receipt-hold"
mkdir "$hold"
set +e
( invoke_plugin "$home" apply '' tmux-plugin-before-receipt-commit "$hold" > "$TEST_ROOT/receipt-race.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/receipt-race.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/tmux-plugin-before-receipt-commit.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/tmux-plugin-before-receipt-commit.ready" ]] || fail 'receipt race did not reach post-write verification hold'
receipt="$home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
printf '{"same_uid_race":true}\n' > "$receipt"
chmod 0600 "$receipt"
: > "$hold/tmux-plugin-before-receipt-commit.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/receipt-race.rc")" == 70 ]] || fail 'changed uncommitted receipt did not preserve status 70'
[[ "$(< "$receipt")" == '{"same_uid_race":true}' ]] || fail 'receipt rollback clobbered concurrent bytes'
assert_contains "$(< "$TEST_ROOT/receipt-race.out")" "$receipt"
pass

# The production staging path has one exact depth-limited fetch and a closed
# credential/protocol environment; it has no full clone command.
tmux_source="$fixture/lib/areas/tmux.sh"
[[ "$(grep -c 'fetch --no-tags --no-recurse-submodules --depth=1 origin "\$commit"' "$tmux_source")" == 1 ]] || \
  fail 'tmux staging does not contain exactly one depth-1 exact-commit fetch'
grep -q -- '-C "\$stage" init --initial-branch=dotfiles-staging' "$tmux_source" || fail 'tmux staging does not initialize an empty repository'
grep -q -- '-C "\$stage" remote add origin "\$repository"' "$tmux_source" || fail 'tmux staging does not set canonical origin before fetch'
grep -q 'GIT_TERMINAL_PROMPT=0' "$tmux_source" || fail 'tmux Git does not disable terminal prompts'
grep -q 'GIT_OPTIONAL_LOCKS=0 tmux_git' "$tmux_source" || fail 'read-only tmux Git does not disable optional index locks'
grep -q -- '-c credential.helper=' "$tmux_source" || fail 'tmux Git does not disable credential helpers'
grep -q -- '-c protocol.allow=never -c protocol.https.allow=always' "$tmux_source" || fail 'tmux Git does not enforce HTTPS-only protocol policy'
[[ "$(grep -c 'tmux_git_readonly clone' "$tmux_source")" == 0 ]] || fail 'tmux staging still performs a full clone'
pass

# The exact framework-only check interface prints runtime-tool actions before
# the complete plugin classification, remains offline, and does not mutate HOME.
host="$TEST_ROOT/host"
home="$(new_home bootstrap-check)"
mkdir -p "$host/etc" "$host/proc/sys/kernel"
printf 'ID="ubuntu"\nVERSION_ID="24.04"\n' > "$host/etc/os-release"
printf '6.8.0-generic\n' > "$host/proc/sys/kernel/osrelease"
: > "$network_log"
set +e
TEST_OUTPUT="$(HOME="$home" PATH=/usr/bin:/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
  DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_BIN=/usr/bin/tmux DOTFILES_TEST_TMUX_OWNER=test-owner \
  DOTFILES_TEST_TMUX_SKIP_ACTIVE=1 DOTFILES_TEST_TMUX_FETCH="$fetch_seam" FIXTURE_REPOS="$repos" \
  NETWORK_LOG="$network_log" "$fixture/bootstrap.sh" --check --provision --area tmux 2>&1)"
TEST_RC=$?
set -e
((TEST_RC != 0)) || fail 'pending bootstrap plugin check unexpectedly converged'
runtime_prefix="${TEST_OUTPUT%%tmux plugin plan*}"
assert_contains "$runtime_prefix" 'provisioning network plan'
assert_contains "$runtime_prefix" 'mise: installed=missing'
assert_contains "$runtime_prefix" 'tmux: target='
assert_contains "$TEST_OUTPUT" 'tpm: action=install network=fetch-exact-depth-1'
[[ ! -s "$network_log" ]] || fail 'offline bootstrap check invoked the fetch seam'
[[ -z "$(/usr/bin/find "$home" -mindepth 1 -print -quit)" ]] || fail 'offline bootstrap check mutated HOME'
pass


# Runtime and plugin provisioning failures gate tmux configuration preflight
# and apply. Terminal statuses survive both provisioning layers.
home="$(new_home runtime-signal)"
mkdir -p "$home/.local/bin" "$TEST_ROOT/runtime-signal-bin"
cat > "$home/.local/bin/mise" <<'SCRIPT'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && printf '2026.7.7 linux-x64\n'
SCRIPT
cat > "$TEST_ROOT/runtime-signal-bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
kill -INT "$$"
SCRIPT
chmod 0755 "$home/.local/bin/mise" "$TEST_ROOT/runtime-signal-bin/curl"
: > "$network_log"
set +e
TEST_OUTPUT="$(HOME="$home" PATH="$home/.local/bin:$TEST_ROOT/runtime-signal-bin:/usr/bin:/bin" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$host" DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_BIN=/usr/bin/tmux \
  DOTFILES_TEST_TMUX_OWNER=test-owner DOTFILES_TEST_TMUX_SKIP_ACTIVE=1 \
  DOTFILES_TEST_TMUX_FETCH="$fetch_seam" FIXTURE_REPOS="$repos" NETWORK_LOG="$network_log" \
  "$fixture/bootstrap.sh" --provision --area tmux 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 130)) || fail 'runtime provisioning signal status was not preserved as 130'
[[ "$TEST_OUTPUT" != *'selected tmux client'* && ! -s "$network_log" && \
  ! -e "$home/.local/state/dotfiles/v1/tmux.json" ]] || fail 'runtime provisioning failure reached tmux plugin/configuration work'
pass

# Plugin-plan preflight preserves reserved rollback and signal statuses exactly.
for terminal_status in 70 130 143; do
  home="$(new_home "plugin-plan-status-$terminal_status")"
  set +e
  TEST_OUTPUT="$(HOME="$home" PATH=/usr/bin:/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
    DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_PLUGIN_PLAN_STATUS="$terminal_status" \
    "$fixture/bootstrap.sh" --check --provision --area tmux 2>&1)"
  TEST_RC=$?
  set -e
  ((TEST_RC == terminal_status)) || fail "tmux plugin plan status $terminal_status was collapsed to $TEST_RC"
done
pass

# The same gate applies to default selection now that tmux is ready.
ready_fixture="$TEST_ROOT/ready-repo"
mkdir "$ready_fixture"
cp -a "$fixture/." "$ready_fixture/"
home="$(new_home ready-runtime-signal)"
mkdir -p "$home/.local/bin"
cp "$TEST_ROOT/home-runtime-signal/.local/bin/mise" "$home/.local/bin/mise"
set +e
TEST_OUTPUT="$(HOME="$home" PATH="$home/.local/bin:$TEST_ROOT/runtime-signal-bin:/usr/bin:/bin" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$host" DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_BIN=/usr/bin/tmux \
  DOTFILES_TEST_TMUX_OWNER=test-owner DOTFILES_TEST_TMUX_SKIP_ACTIVE=1 GIT_USER_NAME='Ready Gate' \
  GIT_USER_EMAIL=ready-gate@example.invalid "$ready_fixture/bootstrap.sh" --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 130)) || fail 'future-ready runtime signal status was not preserved as 130'
[[ "$TEST_OUTPUT" != *'selected tmux client'* && ! -e "$home/.local/state/dotfiles/v1/tmux.json" ]] || \
  fail 'future-ready runtime failure reached tmux configuration preflight or apply'
grep -qxF 'area|tmux|ready' "$fixture/manifests/areas.tsv" || fail 'test changed active tmux readiness semantics'
pass

# In a ready explicit multi-area run, a tmux dependency failure cannot
# temporarily mark tmux preflight-selected and pull its runtime into the plan.
dependency_fixture="$TEST_ROOT/ready-dependency-repo"
mkdir "$dependency_fixture"
cp -a "$ready_fixture/." "$dependency_fixture/"
sed -i 's/|tmux|apply,check|generic,wsl|infocmp|/|tmux|apply,check|generic,wsl|stage7-missing-terminfo|/' \
  "$dependency_fixture/manifests/dependencies.tsv"
home="$(new_home ready-dependency)"
set +e
TEST_OUTPUT="$(HOME="$home" PATH=/usr/bin:/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
  DOTFILES_TEST_ARCH=x86_64 GIT_USER_NAME='Ready Dependency' GIT_USER_EMAIL=ready-dependency@example.invalid \
  "$dependency_fixture/bootstrap.sh" --check --provision --area tmux --area git 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'future-ready tmux dependency failure had the wrong aggregate status'
assert_contains "$TEST_OUTPUT" 'sudo apt-get install -y ncurses-base'
[[ "$TEST_OUTPUT" != *'tmux: target='* && "$TEST_OUTPUT" != *'mise: installed=missing'* ]] || \
  fail 'dependency-failed future-ready tmux was selected for provisioning'
pass

# A production-path WSL integration keeps native_minimum=3.5, rejects Ubuntu
# 24.04's package-owned tmux 3.4, installs the exact locked 3.7b archive, selects
# its receipted launcher without the owner override, then provisions plugins and
# applies the five-target WSL configuration.
[[ "$(jq -r '.tools[] | select(.id == "tmux") | .native_minimum' "$fixture/manifests/provisioning.json")" == 3.5 ]] || \
  fail 'production WSL integration lost the real tmux native minimum'
tmux_archive="${TMUX_37B_ARCHIVE:-/tmp/opencode/stage5-artifacts/tmux.tar.gz}"
[[ -f "$tmux_archive" && "$(sha256sum "$tmux_archive" | cut -d' ' -f1)" == \
  f85e6c1c412750a774eb3f370f33bad05fc726fb8b6a0b174ad6f0b6d954df58 ]] || \
  fail 'locked tmux 3.7b archive fixture is unavailable or drifted'
wsl_host="$TEST_ROOT/wsl-host"
mkdir -p "$wsl_host/etc" "$wsl_host/proc/sys/kernel"
printf 'ID="ubuntu"\nVERSION_ID="24.04"\n' > "$wsl_host/etc/os-release"
printf '5.15.153.1-microsoft-standard-WSL2\n' > "$wsl_host/proc/sys/kernel/osrelease"
runtime_bin="$TEST_ROOT/wsl-runtime-bin"
mkdir "$runtime_bin"
cat > "$runtime_bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
headers=""; destination=""; url=""
while (($#)); do
  case "$1" in
    --dump-header) headers="$2"; shift ;;
    --output) destination="$2"; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
[[ "$url" == 'https://github.com/tmux/tmux-builds/releases/download/v3.7b/tmux-3.7b-linux-x86_64.tar.gz' ]] || exit 98
cp "$LOCKED_TMUX_ARCHIVE" "$destination"
printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
printf 'tmux-3.7b-artifact\n' >> "$RUNTIME_NETWORK_LOG"
SCRIPT
chmod 0755 "$runtime_bin/curl"
home="$(new_home wsl-production)"
mkdir -p "$home/.local/bin"
cat > "$home/.local/bin/mise" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  --version) printf '2026.7.7 linux-x64\n' ;;
  link)
    spec="$2"; root="$3"; backend="${spec%@*}"; version="${spec##*@}"
    backend="${backend#core:}"; backend="${backend//:/-}"; backend="${backend//\//-}"
    mkdir -p "$MISE_DATA_DIR/installs/$backend"
    ln -s "$root" "$MISE_DATA_DIR/installs/$backend/$version"
    ;;
  *) exit 90 ;;
esac
SCRIPT
chmod 0755 "$home/.local/bin/mise"
: > "$network_log"
runtime_network_log="$TEST_ROOT/wsl-runtime-network.log"; : > "$runtime_network_log"
set +e
TEST_OUTPUT="$(HOME="$home" PATH="$home/.local/bin:$runtime_bin:/usr/bin:/bin" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$wsl_host" DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_SKIP_ACTIVE=1 \
  DOTFILES_TEST_TMUX_FETCH="$fetch_seam" FIXTURE_REPOS="$repos" NETWORK_LOG="$network_log" \
  LOCKED_TMUX_ARCHIVE="$tmux_archive" RUNTIME_NETWORK_LOG="$runtime_network_log" \
  "$fixture/bootstrap.sh" --provision --area tmux 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 0)) || fail 'production-path WSL tmux provisioning apply failed'
assert_contains "$TEST_OUTPUT" "detected host class 'supported-wsl'; selected profile 'wsl'"
assert_contains "$TEST_OUTPUT" 'tmux: target=3.7b'
assert_contains "$TEST_OUTPUT" "selected tmux client 3.7b owner=locked-mise:tmux executable=$home/.local/share/dotfiles/provisioning/tools/tmux/3.7b/tmux"
[[ "$(< "$runtime_network_log")" == tmux-3.7b-artifact ]] || fail 'WSL integration did not use exactly the locked runtime artifact seam'
[[ "$(wc -l < "$network_log")" == 4 ]] || fail 'WSL integration did not provision the exact four-plugin closure'
receipt="$home/.local/state/dotfiles/provisioning/v1/receipt.json"
launcher_receipt_hash="$(sha256sum "$home/.local/bin/tmux" | cut -d' ' -f1)"
jq -e --arg root '.local/share/dotfiles/provisioning/tools/tmux/3.7b' --arg launcher_hash "$launcher_receipt_hash" '
  [.tools[] | select(.id == "tmux")] == [{id:"tmux",backend:"aqua:tmux/tmux-builds",version:"3.7b",
    platform:"linux-x86_64",install_root:$root,executable:"tmux",
    executable_sha256:"f3fe7b44391b40f4e4e02b88e4b1af9551be0de926db6bf6c6f3b43b4f1f3bcd"}] and
  [.launchers[] | select(.tool_id == "tmux")] == [{tool_id:"tmux",destination:".local/bin/tmux",
    content_sha256:$launcher_hash}]
' "$receipt" >/dev/null || fail 'WSL integration did not commit exact combined tmux and launcher metadata'
"$home/.local/bin/tmux" -V | grep -qxF 'tmux 3.7b' || fail 'WSL protected launcher did not select locked tmux 3.7b'
invoke_plugin "$home" exact >/dev/null || fail 'WSL integration plugin closure is not exactly receipted'
state="$home/.local/state/dotfiles/v1/tmux.json"
jq -e '.profile == "wsl" and (.targets | map(.path) | sort) == ([
  ".config/dotfiles/upstream/tmux/tmux.conf", ".config/dotfiles/tmux/generic.conf",
  ".config/dotfiles/tmux/persistence.conf", ".config/dotfiles/tmux/wsl.conf",
  ".config/tmux/tmux.conf"] | sort)' "$state" >/dev/null || fail 'WSL integration did not apply the exact WSL tmux configuration'
pass

plugin_signal_seam="$TEST_ROOT/plugin-signal-seam"
cat > "$plugin_signal_seam" <<'SCRIPT'
#!/usr/bin/env bash
exit 143
SCRIPT
chmod 0755 "$plugin_signal_seam"
plugin_signal_home="$TEST_ROOT/home-wsl-production"
rm -rf "$plugin_signal_home/.tmux" "$plugin_signal_home/.config" "$plugin_signal_home/.local/state/dotfiles/v1"
rm -f "$plugin_signal_home/.local/state/dotfiles/provisioning/v1/tmux-plugins.json"
set +e
TEST_OUTPUT="$(HOME="$plugin_signal_home" PATH="$plugin_signal_home/.local/bin:/usr/bin:/bin" DOTFILES_TESTING=1 \
  DOTFILES_TEST_HOST_ROOT="$wsl_host" DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_SKIP_ACTIVE=1 \
  DOTFILES_TEST_TMUX_FETCH="$plugin_signal_seam" \
  "$fixture/bootstrap.sh" --provision --area tmux 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 143)) || fail 'plugin provisioning signal status was not preserved as 143'
[[ "$TEST_OUTPUT" != *'selected tmux client'* && ! -e "$plugin_signal_home/.local/state/dotfiles/v1/tmux.json" ]] || \
  fail 'plugin provisioning failure reached tmux configuration preflight or apply'
pass

# No-area provisioning never selects plugins, and a multi-area provisioning
# command does not implicitly request the tmux plugin operation.
home="$(new_home no-area)"
: > "$network_log"
set +e
TEST_OUTPUT="$(HOME="$home" PATH=/usr/bin:/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
  DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_TMUX_FETCH="$fetch_seam" FIXTURE_REPOS="$repos" \
  NETWORK_LOG="$network_log" GIT_USER_NAME='Stage Seven User' GIT_USER_EMAIL=stage7@example.invalid \
  "$fixture/bootstrap.sh" --check --provision 2>&1)"
TEST_RC=$?
set -e
[[ "$TEST_OUTPUT" != *'tmux plugin plan'* && ! -s "$network_log" ]] || fail 'no-area provisioning selected tmux plugins'
[[ -z "$(/usr/bin/find "$home" -mindepth 1 -print -quit)" ]] || fail 'no-area provisioning check mutated HOME'
set +e
TEST_OUTPUT="$(HOME="$home" PATH=/usr/bin:/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
  GIT_USER_NAME='Stage Seven User' GIT_USER_EMAIL=stage7@example.invalid \
  "$fixture/bootstrap.sh" --check --provision --area tmux --area git 2>&1)"
TEST_RC=$?
set -e
((TEST_RC != 0)) || fail 'combined explicit provisioning accepted an unreceipted tmux closure'
assert_contains "$TEST_OUTPUT" 'pending locked provisioning: tmux'
[[ "$TEST_OUTPUT" != *'tmux plugin plan'* && "$TEST_OUTPUT" != *"area 'tmux' is framework-only"* ]] || \
  fail 'combined explicit provisioning selected the plugin operation or retained framework semantics'
pass

# =============================================================================
# Section 3: tmux parser fixture tool (from stage7_tmux_parser_fixture_test.sh)
# =============================================================================

[[ -x "$FIXTURES" ]] || fail 'tmux parser fixture operation is not executable'
bash -n "$FIXTURES" || fail 'tmux parser fixture operation has invalid Bash syntax'

mkdir "$TEST_ROOT/cache"
chmod 0700 "$TEST_ROOT/cache"
install_network_sentinels "$TEST_ROOT" no-git
cp "$TEST_ROOT/fake-bin/curl" "$TEST_ROOT/fake-bin/dpkg"
HOME="$TEST_ROOT" PATH="$TEST_ROOT/fake-bin:/usr/bin:/bin" "$FIXTURES" validate-lock >/dev/null || \
  fail 'offline tmux parser fixture lock validation failed'
[[ ! -e "$TEST_ROOT/network-attempted" ]] || fail 'fixture lock validation invoked a network or package-install command'

set +e
TEST_OUTPUT="$(HOME="$TEST_ROOT" PATH="$TEST_ROOT/fake-bin:/usr/bin:/bin" "$FIXTURES" verify --root "$TEST_ROOT/cache" 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'offline fixture verification accepted a missing managed root'
[[ "$TEST_OUTPUT" == *"prepare it with: $FIXTURES sync --root $TEST_ROOT/cache"* ]] || \
  fail 'missing fixture verification did not print the precise preparation command'
[[ ! -e "$TEST_ROOT/network-attempted" ]] || fail 'offline fixture verification invoked a network or package-install command'

# Cache roots and every managed object chain are EUID-owned real paths. Writable
# roots, symlinked path components, and nested generation symlinks refuse.
unsafe="$TEST_ROOT/unsafe-cache"
mkdir "$unsafe"; chmod 0777 "$unsafe"
set +e
TEST_OUTPUT="$("$FIXTURES" verify --root "$unsafe" 2>&1)"; status=$?
set -e
[[ "$status" != 0 && ( "$TEST_OUTPUT" == *'must not be group- or world-writable'* || \
  "$TEST_OUTPUT" == *'unsafe writable path component'* ) ]] || \
  fail 'fixture verification accepted an unsafe writable cache root'
mkdir "$TEST_ROOT/real-parent"; ln -s "$TEST_ROOT/real-parent" "$TEST_ROOT/link-parent"
set +e
TEST_OUTPUT="$("$FIXTURES" verify --root "$TEST_ROOT/link-parent" 2>&1)"; status=$?
set -e
[[ "$status" != 0 && ( "$TEST_OUTPUT" == *'symlinked path component'* || \
  "$TEST_OUTPUT" == *'existing, non-symlink directory'* ) ]] || \
  fail 'fixture verification accepted a symlinked cache-root component'

nested="$TEST_ROOT/nested-cache"; mkdir "$nested"
generation="$nested/.tmux-parser-fixtures-generation.unsafe"; mkdir -p "$generation/ubuntu-jammy-tmux-3-2a-amd64/usr/bin"
ln -s /usr/bin/tmux "$generation/ubuntu-jammy-tmux-3-2a-amd64/usr/bin/tmux"
ln -s "${generation##*/}" "$nested/tmux-parser-fixtures-v1"
set +e
TEST_OUTPUT="$("$FIXTURES" verify --root "$nested" 2>&1)"; status=$?
set -e
[[ "$status" != 0 && "$TEST_OUTPUT" == *'nested symlinks'* ]] || \
  fail 'fixture verification accepted a nested managed symlink'

# Shared verification locks coexist, while an exclusive sync waits for readers.
shared_a="$TEST_ROOT/shared-a"; shared_b="$TEST_ROOT/shared-b"; mkdir "$shared_a" "$shared_b"
set +e
DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-after-shared-lock DOTFILES_TEST_HOLD_DIR="$shared_a" \
  "$FIXTURES" verify --root "$TEST_ROOT/cache" > "$TEST_ROOT/shared-a.out" 2>&1 &
pid_a=$!
DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-after-shared-lock DOTFILES_TEST_HOLD_DIR="$shared_b" \
  "$FIXTURES" verify --root "$TEST_ROOT/cache" > "$TEST_ROOT/shared-b.out" 2>&1 &
pid_b=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ -e "$shared_a/fixture-after-shared-lock.ready" && -e "$shared_b/fixture-after-shared-lock.ready" ]] && break
  sleep 0.01
done
[[ -e "$shared_a/fixture-after-shared-lock.ready" && -e "$shared_b/fixture-after-shared-lock.ready" ]] || \
  fail 'shared fixture verification locks did not coexist'
exclusive="$TEST_ROOT/exclusive"; mkdir "$exclusive"
set +e
DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-after-exclusive-lock DOTFILES_TEST_HOLD_DIR="$exclusive" \
  "$FIXTURES" sync --root "$TEST_ROOT/cache" > "$TEST_ROOT/exclusive.out" 2>&1 &
pid_exclusive=$!
set -e
sleep 0.1
[[ ! -e "$exclusive/fixture-after-exclusive-lock.ready" ]] || fail 'exclusive fixture sync bypassed active shared locks'
: > "$shared_a/fixture-after-shared-lock.release"; : > "$shared_b/fixture-after-shared-lock.release"
wait "$pid_a" || true; wait "$pid_b" || true
for ((attempt=0; attempt<500; attempt++)); do [[ -e "$exclusive/fixture-after-exclusive-lock.ready" ]] && break; sleep 0.01; done
[[ -e "$exclusive/fixture-after-exclusive-lock.ready" ]] || fail 'exclusive fixture sync did not acquire the released cache-root lock'
kill -TERM "$pid_exclusive"
wait "$pid_exclusive" || true

# Publication adversaries use an already prepared real cache and never fetch.
# The aggregate suite remains offline when no explicit cache is supplied.
REAL_CACHE="${TMUX_PARSER_FIXTURE_ROOT:-}"
if [[ -n "$REAL_CACHE" ]]; then
  "$FIXTURES" verify --root "$REAL_CACHE" >/dev/null || fail 'selected publication-test fixture cache is invalid'
  publication="$TEST_ROOT/publication-cache"; mkdir "$publication"; cp -a "$REAL_CACHE/archives" "$publication/"
  "$FIXTURES" sync --root "$publication" >/dev/null || fail 'publication test could not seed its managed generation'
  old_target="$(readlink "$publication/tmux-parser-fixtures-v1")"
  set +e
  TEST_OUTPUT="$(DOTFILES_TESTING=1 DOTFILES_TEST_FAIL_AT=fixture-after-publication \
    "$FIXTURES" sync --root "$publication" 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 ]] || fail 'post-publication interruption seam unexpectedly succeeded'
  "$FIXTURES" verify --root "$publication" >/dev/null || fail 'interruption deleted the newly active generation'
  new_target="$(readlink "$publication/tmux-parser-fixtures-v1")"
  [[ "$new_target" != "$old_target" && -d "$publication/$old_target" ]] || \
    fail 'publication immediately deleted the previous reader generation'

  cas="$TEST_ROOT/cas-cache"; mkdir "$cas"; cp -a "$REAL_CACHE/archives" "$cas/"
  "$FIXTURES" sync --root "$cas" >/dev/null
  active="$(readlink "$cas/tmux-parser-fixtures-v1")"
  cp -a "$cas/$active" "$cas/.tmux-parser-fixtures-generation.concurrent"
  hold="$TEST_ROOT/cas-hold"; mkdir "$hold"
  set +e
  ( DOTFILES_TESTING=1 DOTFILES_TEST_HOLD_AT=fixture-before-publish-cas DOTFILES_TEST_HOLD_DIR="$hold" \
      "$FIXTURES" sync --root "$cas" > "$TEST_ROOT/cas.out" 2>&1; printf '%s' "$?" > "$TEST_ROOT/cas.rc" ) &
  cas_pid=$!
  set -e
  for ((attempt=0; attempt<500; attempt++)); do [[ -e "$hold/fixture-before-publish-cas.ready" ]] && break; sleep 0.01; done
  [[ -e "$hold/fixture-before-publish-cas.ready" ]] || fail 'fixture CAS race did not reach publication hold'
  ln -s .tmux-parser-fixtures-generation.concurrent "$cas/concurrent-link"
  mv -fT "$cas/concurrent-link" "$cas/tmux-parser-fixtures-v1"
  : > "$hold/fixture-before-publish-cas.release"
  wait "$cas_pid" || true
  [[ "$(< "$TEST_ROOT/cas.rc")" != 0 && "$(readlink "$cas/tmux-parser-fixtures-v1")" == .tmux-parser-fixtures-generation.concurrent ]] || \
    fail 'fixture publication CAS overwrote a concurrent managed-link update'
  [[ "$(< "$TEST_ROOT/cas.out")" == *'changed since preflight'* ]] || fail 'fixture CAS mismatch was not reported'

  wrapper34="$TEST_ROOT/tmux-3.4-wrapper"
  printf '#!/usr/bin/env bash\nprintf "tmux 3.4\\n"\n' > "$wrapper34"; chmod 0755 "$wrapper34"
  set +e
  TEST_OUTPUT="$("$TEST_DIR/tmux_parser_gate.sh" --fixture-root "$REAL_CACHE" \
    --tmux-3.4 "$wrapper34" --tmux-3.7b-root "$HOME/.local/share/dotfiles/provisioning/tools/tmux/3.7b" 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 && "$TEST_OUTPUT" == *'direct /usr/bin/tmux executable'* ]] || \
    fail 'real-parser identity gate accepted a tmux 3.4 version wrapper'
  wrapper37="$TEST_ROOT/tmux-3.7b-wrapper"; mkdir "$wrapper37"
  printf '#!/usr/bin/env bash\nprintf "tmux 3.7b\\n"\n' > "$wrapper37/tmux"; chmod 0755 "$wrapper37/tmux"
  set +e
  TEST_OUTPUT="$("$TEST_DIR/tmux_parser_gate.sh" --fixture-root "$REAL_CACHE" \
    --tmux-3.7b-root "$wrapper37" 2>&1)"; status=$?
  set -e
  [[ "$status" != 0 && "$TEST_OUTPUT" == *'mode, size, or SHA-256 differs'* ]] || \
    fail 'real-parser identity gate accepted a tmux 3.7b version wrapper'
fi

jq -e '
  .schema_version == 1 and .managed_root == "tmux-parser-fixtures-v1" and
  .extractor == ["dpkg-deb", "--extract"] and (.fixtures | length == 1)
' "$REPO_DIR/manifests/tmux-parser-fixtures.lock.json" >/dev/null || \
  fail 'tmux parser fixture lock lost its static contract'

if grep -Eq 'tmux-parser-fixtures[[:space:]]+sync' \
  "$REPO_DIR/bootstrap.sh" "$REPO_DIR"/lib/*.sh "$REPO_DIR"/lib/areas/*.sh; then
  fail 'bootstrap or library code can invoke tmux parser fixture sync'
fi
pass

printf 'PASS: %d tmux test groups\n' "$TEST_COUNT"
