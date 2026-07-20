#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""
TEST_RC=0

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT
fail() { printf 'FAIL: %s\n%s\n' "$*" "$TEST_OUTPUT" >&2; exit 1; }
pass() { ((TEST_COUNT += 1)); }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"; }

host="$TEST_ROOT/host"
mkdir -p "$host/etc" "$host/proc/sys/kernel"
printf 'ID="ubuntu"\nVERSION_ID="24.04"\n' > "$host/etc/os-release"
printf '6.8.0-generic\n' > "$host/proc/sys/kernel/osrelease"

fixture="$TEST_ROOT/repo"
mkdir "$fixture"
cp -a "$REPO_DIR/." "$fixture/"
# Stage 5 exercises provisioning independently of later default-ready areas.
sed -i 's/^area|bash|ready$/area|bash|framework/; s/^area|tmux|ready$/area|tmux|framework/; s/^area|nvim|ready$/area|nvim|framework/; s/^area|zsh|ready$/area|zsh|framework/' \
  "$fixture/manifests/areas.tsv"

mise_artifact="$TEST_ROOT/mise-artifact"
tool_artifact="$TEST_ROOT/starship-artifact"
cat > "$mise_artifact" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  --version) printf '2026.7.7 linux-x64\n' ;;
  where)
    spec="$2"
    backend="${spec%@*}"
    version="${spec##*@}"
    backend="${backend//:/-}"
    backend="${backend//\//-}"
    link="$MISE_DATA_DIR/installs/$backend/$version"
    [[ -L "$link" ]] || exit 1
    readlink -f "$link"
    ;;
  link)
    spec="$2"
    root="$3"
    backend="${spec%@*}"
    version="${spec##*@}"
    backend="${backend//:/-}"
    backend="${backend//\//-}"
    mkdir -p "$MISE_DATA_DIR/installs/$backend"
    ln -s "$root" "$MISE_DATA_DIR/installs/$backend/$version"
    ;;
  *) printf 'unexpected fake mise invocation: %s\n' "$*" >&2; exit 90 ;;
esac
SCRIPT
cat > "$tool_artifact" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then printf 'starship 1.26.0\n'; else exit 91; fi
SCRIPT
chmod +x "$mise_artifact" "$tool_artifact"
mise_hash="$(sha256sum "$mise_artifact" | cut -d' ' -f1)"
tool_hash="$(sha256sum "$tool_artifact" | cut -d' ' -f1)"
jq --arg mise_hash "$mise_hash" --arg tool_hash "$tool_hash" '
  .mise.artifact.url="https://fixtures.invalid/mise" |
  .mise.artifact.sha256=$mise_hash |
  .mise.artifact.inventory_sha256=$mise_hash |
  .mise.artifact.allowed_origins=["fixtures.invalid"] |
  .tools=[.tools[] | select(.id == "starship")] |
  .tools[0].scope="core" |
  .tools[0].areas=[] |
  .tools[0].owner_policy="locked-mise" |
  del(.tools[0].native_minimum) |
  del(.tools[0].native_package) |
  .tools[0].artifact.url="https://fixtures.invalid/starship" |
  .tools[0].artifact.sha256=$tool_hash |
  .tools[0].artifact.inventory_sha256=$tool_hash |
  .tools[0].artifact.format="raw" |
  .tools[0].artifact.strip_components=0 |
  .tools[0].artifact.executable="starship" |
  .tools[0].artifact.allowed_origins=["fixtures.invalid"] |
  .tools[0].commands[0].path="starship"
' "$fixture/manifests/provisioning.json" > "$fixture/manifests/provisioning.json.new"
mv "$fixture/manifests/provisioning.json.new" "$fixture/manifests/provisioning.json"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cat > "$fake_bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${DENY_DOWNLOAD:-}" != 1 ]] || { printf 'network sentinel invoked\n' >&2; exit 99; }
headers=""
destination=""
url=""
while (($#)); do
  case "$1" in
    --dump-header) headers="$2"; shift ;;
    --output) destination="$2"; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
case "$url" in
  https://fixtures.invalid/mise) cp "$FIXTURE_MISE" "$destination" ;;
  https://fixtures.invalid/starship) cp "$FIXTURE_TOOL" "$destination" ;;
  *) exit 98 ;;
esac
printf 'HTTP/1.1 200 OK\r\n\r\n' > "$headers"
SCRIPT
chmod +x "$fake_bin/curl"

new_home() { local path="$TEST_ROOT/home-$1"; mkdir "$path"; printf '%s' "$path"; }
invoke_fixture() {
  local home="$1"; shift
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
    XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" \
    PATH="$home/.local/bin:$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
    DOTFILES_TEST_HOST_ROOT="$host" FIXTURE_MISE="$mise_artifact" FIXTURE_TOOL="$tool_artifact" \
    GIT_USER_NAME='Stage Five User' GIT_USER_EMAIL='stage5@example.com' "$fixture/bootstrap.sh" "$@"
}
capture() {
  local home="$1"; shift
  set +e
  TEST_OUTPUT="$(invoke_fixture "$home" "$@" 2>&1)"
  TEST_RC=$?
  set -e
}

# The active lock and both schemas are strict JSON and exclude deferred tools.
jq -e '.schema_version == 1 and ([.tools[].id] | index("opencode") == null) and ([.tools[].id] | index("vite+") == null)' \
  "$REPO_DIR/manifests/provisioning.json" >/dev/null || fail 'active provisioning lock is invalid'
jq empty "$REPO_DIR/schemas/provisioning-manifest-v1.schema.json" \
  "$REPO_DIR/schemas/provisioning-receipt-v1.schema.json" || fail 'provisioning schema JSON is invalid'
pass

# Mise stores core backend links under the canonical tool name.
core_link="$(HOME="$TEST_ROOT/core-link-home" DOTFILES_DIR="$REPO_DIR" bash -c \
  'source "$DOTFILES_DIR/lib/provisioning.sh"; mise_link_path core:node 24.18.0')"
[[ "$core_link" == "$TEST_ROOT/core-link-home/.local/share/mise/installs/node/24.18.0" ]] || \
  fail 'core mise backend path was not canonicalized'
pass

# CLI intent is explicit and area selection does not pull in the core set.
home="$(new_home cli)"
capture "$home" --provision --remove
((TEST_RC == 1)) || fail '--provision --remove unexpectedly succeeded'
assert_contains "$TEST_OUTPUT" '--provision is invalid with --remove'
capture "$home" --check --provision --area git
((TEST_RC == 0)) || fail 'area-scoped provisioning without mapped tools failed'
assert_contains "$TEST_OUTPUT" 'no retained tools are mapped to the selected areas'
[[ ! -e "$home/.local/bin/mise" ]] || fail 'area-scoped Git provisioning selected mise'
pass

# Provisioning check is offline, reports pending locks, and preserves unrelated OpenCode data.
home="$(new_home offline)"
mkdir -p "$home/.config/opencode" "$home/.local/share/mise/installs/opencode/9.9.9"
printf 'preserve-auth-and-config\n' > "$home/.config/opencode/opencode.json"
printf 'preserve-executable\n' > "$home/.local/share/mise/installs/opencode/9.9.9/opencode"
before_config="$(sha256sum "$home/.config/opencode/opencode.json")"
before_binary="$(sha256sum "$home/.local/share/mise/installs/opencode/9.9.9/opencode")"
DENY_DOWNLOAD=1 capture "$home" --check --provision
((TEST_RC == 1)) || fail 'unconverged provisioning check did not return 1'
assert_contains "$TEST_OUTPUT" 'provisioning network plan'
assert_contains "$TEST_OUTPUT" 'pending locked provisioning: starship'
[[ "$before_config" == "$(sha256sum "$home/.config/opencode/opencode.json")" ]] || fail 'OpenCode config changed during check'
[[ "$before_binary" == "$(sha256sum "$home/.local/share/mise/installs/opencode/9.9.9/opencode")" ]] || fail 'OpenCode install changed during check'
[[ ! -e "$home/.local/bin/mise" ]] || fail 'check installed mise'
pass

# Apply installs only verified fixture bytes, links the backend, and writes retained ownership receipts.
capture "$home" --provision
((TEST_RC == 0)) || fail 'fixture provisioning apply failed'
[[ -x "$home/.local/bin/mise" && -x "$home/.local/bin/starship" ]] || fail 'mise or protected launcher was not installed'
receipt="$home/.local/state/dotfiles/provisioning/v1/receipt.json"
jq -e '([.tools[].id] | sort) == ["mise","starship"] and .launchers[0].destination == ".local/bin/starship"' "$receipt" >/dev/null || \
  fail 'retained provisioning receipt is incomplete'
[[ "$before_config" == "$(sha256sum "$home/.config/opencode/opencode.json")" ]] || fail 'OpenCode config changed during apply'
[[ "$before_binary" == "$(sha256sum "$home/.local/share/mise/installs/opencode/9.9.9/opencode")" ]] || fail 'OpenCode install changed during apply'
pass

# A second provisioning check converges without invoking the downloader.
DENY_DOWNLOAD=1 capture "$home" --check --provision
((TEST_RC == 0)) || fail 'converged provisioning check failed'
assert_contains "$TEST_OUTPUT" 'starship is converged'
pass

# General receipts are exact regular EUID-owned mode-0600 objects.
chmod 0644 "$receipt"
capture "$home" --check --provision
((TEST_RC != 0)) || fail 'unsafe provisioning receipt mode was accepted'
assert_contains "$TEST_OUTPUT" 'provisioning receipt has an unsafe owner or mode'
chmod 0600 "$receipt"
symlink_receipt_home="$(new_home receipt-symlink)"
mkdir -p "$symlink_receipt_home/.local/state/dotfiles/provisioning/v1"
ln -s "$receipt" "$symlink_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json"
capture "$symlink_receipt_home" --check
((TEST_RC != 0)) || fail 'symlinked provisioning receipt was accepted'
assert_contains "$TEST_OUTPUT" 'provisioning receipt is symlinked or not a regular file'
pass

# Validation itself is bound to the exact identity whose schema and ownership
# were checked, not merely to the same pathname before later provisioning.
hold="$TEST_ROOT/receipt-validation-hold"
mkdir "$hold"
cp "$receipt" "$TEST_ROOT/receipt-before-validation-race"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=after-provisioning-receipt-validation-read DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$home" --check > "$TEST_ROOT/receipt-validation-race.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/receipt-validation-race.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/after-provisioning-receipt-validation-read.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/after-provisioning-receipt-validation-read.ready" ]] || fail 'receipt validation race did not reach its exact-read hold'
printf '{"validation_race":true}\n' > "$receipt.concurrent"
chmod 0600 "$receipt.concurrent"
mv -T "$receipt.concurrent" "$receipt"
: > "$hold/after-provisioning-receipt-validation-read.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/receipt-validation-race.rc")" != 0 ]] || fail 'receipt replacement during validation was accepted'
[[ "$(< "$receipt")" == '{"validation_race":true}' ]] || fail 'validation race changed concurrent receipt bytes'
assert_contains "$(< "$TEST_ROOT/receipt-validation-race.out")" 'provisioning receipt changed during validation'
cp "$TEST_ROOT/receipt-before-validation-race" "$receipt"
chmod 0600 "$receipt"
pass

# Every receipt read-modify-write CASes the exact version read. Replacing the
# receipt at the read hold preserves concurrent bytes and refuses the update.
rm "$home/.local/bin/starship"
hold="$TEST_ROOT/receipt-cas-hold"
mkdir "$hold"
cp "$receipt" "$TEST_ROOT/receipt-before-cas"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=after-provisioning-receipt-read DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$home" --provision > "$TEST_ROOT/receipt-cas.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/receipt-cas.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/after-provisioning-receipt-read.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/after-provisioning-receipt-read.ready" ]] || fail 'receipt CAS test did not reach the exact-read hold'
printf '{"concurrent_receipt":true}\n' > "$receipt.concurrent"
chmod 0600 "$receipt.concurrent"
mv -T "$receipt.concurrent" "$receipt"
: > "$hold/after-provisioning-receipt-read.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/receipt-cas.rc")" != 0 ]] || fail 'receipt CAS race unexpectedly succeeded'
[[ "$(< "$receipt")" == '{"concurrent_receipt":true}' ]] || fail 'receipt CAS race overwrote concurrent bytes'
assert_contains "$(< "$TEST_ROOT/receipt-cas.out")" 'provisioning receipt changed while it was read'
cp "$TEST_ROOT/receipt-before-cas" "$receipt"
chmod 0600 "$receipt"
capture "$home" --provision
((TEST_RC == 0)) && [[ -x "$home/.local/bin/starship" ]] || fail 'transactional launcher rollback did not repair cleanly'
pass

# Tool convergence requires the exact launcher receipt row, not only matching
# launcher bytes. A forged hash makes the retained owner pending.
cp "$receipt" "$TEST_ROOT/receipt-before-launcher-hash"
jq '(.launchers[] | select(.tool_id == "starship") | .content_sha256)="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$receipt" > "$receipt.new"
mv "$receipt.new" "$receipt"; chmod 0600 "$receipt"
capture "$home" --check --provision
((TEST_RC == 1)) || fail 'forged launcher receipt hash was accepted as converged'
assert_contains "$TEST_OUTPUT" 'starship: target='
cp "$TEST_ROOT/receipt-before-launcher-hash" "$receipt"; chmod 0600 "$receipt"
pass

# Root, mise link, launcher, and both metadata rows share one commit boundary.
# Faults at every post-install phase restore the exact absent pre-state.
for point in provisioning-tool-after-root provisioning-tool-after-link provisioning-tool-after-launcher \
  provisioning-tool-before-combined-receipt provisioning-tool-after-combined-receipt; do
  tx_home="$(new_home "transaction-$point")"
  mkdir -p "$tx_home/.local/bin"
  cp "$mise_artifact" "$tx_home/.local/bin/mise"; chmod 0755 "$tx_home/.local/bin/mise"
  set +e
  TEST_OUTPUT="$(DOTFILES_TEST_FAIL_AT="$point" invoke_fixture "$tx_home" --provision 2>&1)"
  TEST_RC=$?
  set -e
  ((TEST_RC != 0 && TEST_RC != 70)) || fail "$point returned the wrong transaction status"
  tx_root_rel="$(jq -r '.tools[0].install_root' "$fixture/manifests/provisioning.json")"
  tx_link="$tx_home/.local/share/mise/installs/starship/1.26.0"
  [[ ! -e "$tx_home/$tx_root_rel" && ! -L "$tx_home/$tx_root_rel" &&
    ! -e "$tx_link" && ! -L "$tx_link" && ! -e "$tx_home/.local/bin/starship" &&
    ! -e "$tx_home/.local/state/dotfiles/provisioning/v1/receipt.json" ]] || \
    fail "$point left a partially committed retained-tool transaction"
done
pass

# Initial mise bytes and their first receipt are one CAS transaction. Failures
# after either installation cannot leave an unreceipted binary or stale receipt.
for point in provisioning-mise-after-install provisioning-mise-before-combined-receipt \
  provisioning-tool-after-combined-receipt; do
  mise_tx_home="$(new_home "mise-transaction-$point")"
  set +e
  TEST_OUTPUT="$(DOTFILES_TEST_FAIL_AT="$point" invoke_fixture "$mise_tx_home" --provision 2>&1)"
  TEST_RC=$?
  set -e
  ((TEST_RC != 0 && TEST_RC != 70)) || fail "$point returned the wrong initial mise transaction status"
  [[ ! -e "$mise_tx_home/.local/bin/mise" &&
    ! -e "$mise_tx_home/.local/state/dotfiles/provisioning/v1/receipt.json" ]] || \
    fail "$point left initial mise bytes or a stale receipt"
done

mise_receipt_home="$(new_home mise-receipt-rollback)"
mkdir -p "$mise_receipt_home/.local/state/dotfiles/provisioning/v1"
printf '{"schema_version":1,"manifest_sha256":"%s","tools":[],"launchers":[]}\n' \
  "$(sha256sum "$fixture/manifests/provisioning.json" | cut -d' ' -f1)" > \
  "$mise_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json"
chmod 0600 "$mise_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json"
mise_old_receipt="$(stat -c '%d:%i:%a:%y' -- "$mise_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json"):$(sha256sum "$mise_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json")"
set +e
TEST_OUTPUT="$(DOTFILES_TEST_FAIL_AT=provisioning-tool-after-combined-receipt \
  invoke_fixture "$mise_receipt_home" --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC != 0 && TEST_RC != 70)) || fail 'initial mise receipt replacement fault had the wrong status'
[[ ! -e "$mise_receipt_home/.local/bin/mise" && "$mise_old_receipt" == \
  "$(stat -c '%d:%i:%a:%y' -- "$mise_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json"):$(sha256sum "$mise_receipt_home/.local/state/dotfiles/provisioning/v1/receipt.json")" ]] || \
  fail 'initial mise rollback did not restore the exact quarantined receipt'

mise_signal_home="$(new_home mise-signal)"
set +e
TEST_OUTPUT="$(DOTFILES_TEST_SIGNAL_AT=provisioning-mise-before-commit \
  invoke_fixture "$mise_signal_home" --provision 2>&1)"
TEST_RC=$?
set -e
[[ "$TEST_RC" == 143 && ! -e "$mise_signal_home/.local/bin/mise" &&
  ! -e "$mise_signal_home/.local/state/dotfiles/provisioning/v1/receipt.json" ]] || \
  fail 'initial mise signal left binary or receipt state'
pass

# Launcher repair is the same combined transaction. A failed mode repair
# restores the exact prior launcher and leaves the combined receipt unchanged.
chmod 0644 "$home/.local/bin/starship"
cp -a "$home/.local/bin/starship" "$TEST_ROOT/launcher-before-repair"
cp "$receipt" "$TEST_ROOT/receipt-before-repair"
set +e
TEST_OUTPUT="$(DOTFILES_TEST_FAIL_AT=provisioning-tool-before-combined-receipt invoke_fixture "$home" --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC != 0 && TEST_RC != 70)) || fail 'launcher repair fault had the wrong status'
cmp -s "$home/.local/bin/starship" "$TEST_ROOT/launcher-before-repair" || fail 'launcher repair rollback changed prior bytes'
[[ "$(stat -c %a -- "$home/.local/bin/starship")" == 644 ]] || fail 'launcher repair rollback changed prior mode'
cmp -s "$receipt" "$TEST_ROOT/receipt-before-repair" || fail 'launcher repair fault changed combined metadata'
chmod 0755 "$home/.local/bin/starship"
pass

# Verified receipt installation is the commit point. Cleanup failures after it
# retain exact old recovery paths without rolling back committed new state.
cleanup_home="$(new_home committed-cleanup)"
capture "$cleanup_home" --provision
((TEST_RC == 0)) || fail 'committed-cleanup fixture did not converge'
chmod 0644 "$cleanup_home/.local/bin/starship"
hold="$TEST_ROOT/committed-cleanup-hold"; mkdir "$hold"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=provisioning-tool-after-commit-before-cleanup DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$cleanup_home" --provision > "$TEST_ROOT/committed-cleanup.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/committed-cleanup.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/provisioning-tool-after-commit-before-cleanup.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/provisioning-tool-after-commit-before-cleanup.ready" ]] || fail 'committed cleanup test did not reach its post-commit hold'
mapfile -t cleanup_quarantines < <(/usr/bin/find "$cleanup_home" -name '*.dotfiles-provisioning-quarantine.*' -print)
((${#cleanup_quarantines[@]} == 2)) || fail 'committed cleanup fixture did not retain receipt and launcher rollback objects'
for quarantine in "${cleanup_quarantines[@]}"; do printf '\nchanged after commit\n' >> "$quarantine"; done
: > "$hold/provisioning-tool-after-commit-before-cleanup.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/committed-cleanup.rc")" != 0 ]] || fail 'committed cleanup failure unexpectedly reported success'
cleanup_output="$(< "$TEST_ROOT/committed-cleanup.out")"
for quarantine in "${cleanup_quarantines[@]}"; do
  [[ -e "$quarantine" ]] || fail "committed cleanup deleted retained recovery path: $quarantine"
  assert_contains "$cleanup_output" "$quarantine"
done
[[ -x "$cleanup_home/.local/bin/starship" && "$(stat -c %a -- "$cleanup_home/.local/bin/starship")" == 755 ]] || \
  fail 'committed cleanup failure reverted the new launcher'
jq -e '[.tools[] | select(.id == "starship")] | length == 1' \
  "$cleanup_home/.local/state/dotfiles/provisioning/v1/receipt.json" >/dev/null || \
  fail 'committed cleanup failure reverted the new receipt'
pass

# A same-UID receipt replacement after the combined write is preserved, forces
# status 70, and rolls back the exact root, link, and launcher post-states.
receipt_race_home="$(new_home combined-receipt-race)"
mkdir -p "$receipt_race_home/.local/bin"
cp "$mise_artifact" "$receipt_race_home/.local/bin/mise"; chmod 0755 "$receipt_race_home/.local/bin/mise"
hold="$TEST_ROOT/combined-receipt-race-hold"; mkdir "$hold"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=provisioning-tool-after-combined-receipt DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$receipt_race_home" --provision > "$TEST_ROOT/combined-receipt-race.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/combined-receipt-race.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/provisioning-tool-after-combined-receipt.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/provisioning-tool-after-combined-receipt.ready" ]] || fail 'combined receipt race did not reach its post-write hold'
race_receipt="$receipt_race_home/.local/state/dotfiles/provisioning/v1/receipt.json"
printf '{"combined_receipt_race":true}\n' > "$race_receipt"
chmod 0600 "$race_receipt"
: > "$hold/provisioning-tool-after-combined-receipt.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/combined-receipt-race.rc")" == 70 &&
  "$(< "$race_receipt")" == '{"combined_receipt_race":true}' ]] || \
  fail 'combined receipt race did not preserve concurrent bytes with status 70'
tx_root_rel="$(jq -r '.tools[0].install_root' "$fixture/manifests/provisioning.json")"
[[ ! -e "$receipt_race_home/$tx_root_rel" && ! -e "$receipt_race_home/.local/bin/starship" ]] || \
  fail 'combined receipt race retained exact rollback-safe tool objects'
pass

# A concurrent launcher edit after receipt installation is never deleted during
# rollback. The transaction reports 70 while still removing its unchanged
# receipt, mise link, and root.
launcher_race_home="$(new_home launcher-race)"
mkdir -p "$launcher_race_home/.local/bin"
cp "$mise_artifact" "$launcher_race_home/.local/bin/mise"; chmod 0755 "$launcher_race_home/.local/bin/mise"
hold="$TEST_ROOT/launcher-race-hold"; mkdir "$hold"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=provisioning-tool-before-commit DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$launcher_race_home" --provision > "$TEST_ROOT/launcher-race.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/launcher-race.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/provisioning-tool-before-commit.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/provisioning-tool-before-commit.ready" ]] || fail 'launcher race did not reach the final verification hold'
printf '#!/usr/bin/env bash\nprintf "concurrent launcher\\n"\n' > "$launcher_race_home/.local/bin/starship"
chmod 0755 "$launcher_race_home/.local/bin/starship"
: > "$hold/provisioning-tool-before-commit.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/launcher-race.rc")" == 70 &&
  "$(< "$launcher_race_home/.local/bin/starship")" == $'#!/usr/bin/env bash\nprintf "concurrent launcher\\n"' ]] || \
  fail 'launcher race did not preserve concurrent bytes with status 70'
tx_root_rel="$(jq -r '.tools[0].install_root' "$fixture/manifests/provisioning.json")"
[[ ! -e "$launcher_race_home/$tx_root_rel" &&
  ! -e "$launcher_race_home/.local/state/dotfiles/provisioning/v1/receipt.json" ]] || \
  fail 'launcher race retained unchanged transaction objects'
pass

# Configuration removal retains tools, launchers, receipts, and unrelated OpenCode state.
capture "$home" --remove
((TEST_RC == 0)) || fail 'configuration removal failed'
[[ -x "$home/.local/bin/mise" && -x "$home/.local/bin/starship" && -f "$receipt" ]] || fail 'removal deleted retained provisioning state'
[[ -f "$home/.config/opencode/opencode.json" ]] || fail 'removal deleted OpenCode config'
pass

# Unknown manifest fields and unsafe receipt ownership fail before mutation.
broken="$TEST_ROOT/broken-repo"
mkdir "$broken"
cp -a "$fixture/." "$broken/"
jq '.unexpected=true' "$broken/manifests/provisioning.json" > "$broken/manifests/provisioning.json.new"
mv "$broken/manifests/provisioning.json.new" "$broken/manifests/provisioning.json"
broken_home="$(new_home broken)"
set +e
TEST_OUTPUT="$(HOME="$broken_home" PATH="$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
  DOTFILES_TEST_HOST_ROOT="$host" "$broken/bootstrap.sh" --check 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'unknown provisioning manifest field was accepted'
assert_contains "$TEST_OUTPUT" 'malformed or unknown provisioning manifest'
[[ -z "$(find "$broken_home" -mindepth 1 -print -quit)" ]] || fail 'invalid manifest check mutated HOME'
pass

# A forged receipt owner identity is rejected before any executable probe.
jq '(.tools[] | select(.id == "starship") | .backend)="aqua:evil/shadow"' "$receipt" > "$receipt.new"
mv "$receipt.new" "$receipt"
chmod 0600 "$receipt"
capture "$home" --check --provision
((TEST_RC == 1)) || fail 'forged receipt backend was accepted'
assert_contains "$TEST_OUTPUT" 'receipt owner identity is invalid for starship'
pass

# A higher-precedence project executable blocks protected resolution and is never probed.
# Restore the accepted receipt generated before the identity corruption.
jq --arg backend 'aqua:starship/starship' '(.tools[] | select(.id == "starship") | .backend)=$backend' "$receipt" > "$receipt.new"
mv "$receipt.new" "$receipt"
chmod 0600 "$receipt"
shadow_bin="$TEST_ROOT/project-bin"
mkdir "$shadow_bin"
cat > "$shadow_bin/starship" <<SCRIPT
#!/usr/bin/env bash
printf invoked > "$TEST_ROOT/shadow-invoked"
printf 'starship 1.26.0\n'
SCRIPT
chmod +x "$shadow_bin/starship"
set +e
TEST_OUTPUT="$(HOME="$home" PATH="$shadow_bin:$home/.local/bin:$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
  DOTFILES_TEST_HOST_ROOT="$host" DENY_DOWNLOAD=1 "$fixture/bootstrap.sh" --check --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'project shadow of protected starship was accepted'
assert_contains "$TEST_OUTPUT" "protected command 'starship' is shadowed"
[[ ! -e "$TEST_ROOT/shadow-invoked" ]] || fail 'rejected protected shadow was executed'
pass

# Apply also fails its post-install gate when a protected project shadow remains active.
shadow_apply_home="$(new_home shadow-apply)"
set +e
TEST_OUTPUT="$(HOME="$shadow_apply_home" PATH="$shadow_bin:$shadow_apply_home/.local/bin:$fake_bin:/usr/bin:/bin" \
  DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_HOST_ROOT="$host" \
  FIXTURE_MISE="$mise_artifact" FIXTURE_TOOL="$tool_artifact" GIT_USER_NAME='Stage Five User' \
  GIT_USER_EMAIL='stage5@example.com' "$fixture/bootstrap.sh" --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'provisioning apply accepted a remaining protected shadow'
assert_contains "$TEST_OUTPUT" 'did not converge to its protected owner after installation'
pass

# A hidden symlink at the approved mise destination is never executed.
symlink_home="$(new_home mise-symlink)"
mkdir -p "$symlink_home/.local/bin"
ln -s "$shadow_bin/starship" "$symlink_home/.local/bin/mise"
capture "$symlink_home" --check --provision
((TEST_RC == 1)) || fail 'symlinked hidden mise destination was accepted'
assert_contains "$TEST_OUTPUT" 'user mise must be a directly owned regular executable'
[[ ! -e "$TEST_ROOT/shadow-invoked" ]] || fail 'rejected mise symlink target was executed'
pass

# Checksum and redirect policy failures never install an accepted mise destination.
bad_hash_repo="$TEST_ROOT/bad-hash-repo"
mkdir "$bad_hash_repo"
cp -a "$fixture/." "$bad_hash_repo/"
jq '.mise.artifact.sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$bad_hash_repo/manifests/provisioning.json" > "$bad_hash_repo/manifests/provisioning.json.new"
mv "$bad_hash_repo/manifests/provisioning.json.new" "$bad_hash_repo/manifests/provisioning.json"
bad_hash_home="$(new_home bad-hash)"
set +e
TEST_OUTPUT="$(HOME="$bad_hash_home" PATH="$bad_hash_home/.local/bin:$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
  DOTFILES_TEST_HOST_ROOT="$host" FIXTURE_MISE="$mise_artifact" FIXTURE_TOOL="$tool_artifact" \
  GIT_USER_NAME='Stage Five User' GIT_USER_EMAIL='stage5@example.com' "$bad_hash_repo/bootstrap.sh" --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'mise checksum mismatch was accepted'
assert_contains "$TEST_OUTPUT" 'artifact checksum mismatch for mise'
[[ ! -e "$bad_hash_home/.local/bin/mise" ]] || fail 'checksum failure installed mise'
pass

redirect_bin="$TEST_ROOT/redirect-bin"
mkdir "$redirect_bin"
cat > "$redirect_bin/curl" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
while (($#)); do
  case "$1" in --dump-header) headers="$2"; shift ;; --output) destination="$2"; shift ;; esac
  shift
done
: > "$destination"
printf 'HTTP/1.1 302 Found\r\nLocation: https://evil.invalid/payload\r\n\r\n' > "$headers"
SCRIPT
chmod +x "$redirect_bin/curl"
redirect_home="$(new_home redirect)"
set +e
TEST_OUTPUT="$(HOME="$redirect_home" PATH="$redirect_home/.local/bin:$redirect_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
  DOTFILES_TEST_HOST_ROOT="$host" GIT_USER_NAME='Stage Five User' GIT_USER_EMAIL='stage5@example.com' \
  "$fixture/bootstrap.sh" --provision 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'unapproved redirect origin was accepted'
assert_contains "$TEST_OUTPUT" 'unapproved origin'
[[ ! -e "$redirect_home/.local/bin/mise" ]] || fail 'redirect failure installed mise'
pass


# Destination identity is captured before network/staging. Appeared file and
# directory destinations are preserved without overwrite or directory nesting.
mise_race_home="$(new_home mise-appearance)"
hold="$TEST_ROOT/mise-appearance-hold"
mkdir "$hold"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=provisioning-mise-after-download DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$mise_race_home" --provision > "$TEST_ROOT/mise-appearance.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/mise-appearance.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/provisioning-mise-after-download.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/provisioning-mise-after-download.ready" ]] || fail 'mise appearance test did not reach its network hold'
mkdir "$mise_race_home/.local/bin/mise"
printf 'appeared directory\n' > "$mise_race_home/.local/bin/mise/marker"
: > "$hold/provisioning-mise-after-download.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/mise-appearance.rc")" != 0 ]] || fail 'appeared mise destination was accepted'
[[ "$(< "$mise_race_home/.local/bin/mise/marker")" == 'appeared directory' ]] || fail 'mise appearance race changed destination data'
[[ "$(/usr/bin/find "$mise_race_home/.local/bin/mise" -mindepth 1 ! -name marker -print -quit)" == "" ]] || \
  fail 'mise stage was nested into an appeared directory'
[[ ! -e "$mise_race_home/.local/state/dotfiles/provisioning/v1/receipt.json" ]] || fail 'mise appearance race wrote an ownership receipt'

tool_race_home="$(new_home tool-appearance)"
mkdir -p "$tool_race_home/.local/bin"
cp "$mise_artifact" "$tool_race_home/.local/bin/mise"
chmod 0755 "$tool_race_home/.local/bin/mise"
tool_root_rel="$(jq -r '.tools[0].install_root' "$fixture/manifests/provisioning.json")"
hold="$TEST_ROOT/tool-appearance-hold"
mkdir "$hold"
set +e
( set +e; DOTFILES_TEST_HOLD_AT=provisioning-tool-after-staging DOTFILES_TEST_HOLD_DIR="$hold" \
    invoke_fixture "$tool_race_home" --provision > "$TEST_ROOT/tool-appearance.out" 2>&1; \
  printf '%s' "$?" > "$TEST_ROOT/tool-appearance.rc" ) &
pid=$!
set -e
for ((attempt=0; attempt<500; attempt++)); do
  [[ ! -e "$hold/provisioning-tool-after-staging.ready" ]] || break
  sleep 0.01
done
[[ -e "$hold/provisioning-tool-after-staging.ready" ]] || fail 'tool appearance test did not reach its staging hold'
mkdir -p "$tool_race_home/$tool_root_rel"
printf 'appeared root\n' > "$tool_race_home/$tool_root_rel/marker"
: > "$hold/provisioning-tool-after-staging.release"
wait "$pid" || true
[[ "$(< "$TEST_ROOT/tool-appearance.rc")" != 0 ]] || fail 'appeared retained tool root was accepted'
[[ "$(< "$tool_race_home/$tool_root_rel/marker")" == 'appeared root' ]] || fail 'tool appearance race changed destination data'
[[ ! -e "$tool_race_home/$tool_root_rel/root" && ! -e "$tool_race_home/$tool_root_rel/starship" ]] || \
  fail 'retained tool stage was nested into an appeared root'
[[ ! -e "$tool_race_home/.local/state/dotfiles/provisioning/v1/receipt.json" ]] || fail 'tool appearance race wrote an ownership receipt'
pass

# Archive membership is locked independently from the compressed-byte hash.
archive_root="$TEST_ROOT/archive"
mkdir "$archive_root"
printf 'expected\n' > "$archive_root/tool"
tar -czf "$TEST_ROOT/tool.tar.gz" -C "$archive_root" tool
set +e
HOME="$TEST_ROOT/archive-home" TARGET_ROOT="$TEST_ROOT/archive-home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage5-test \
  bash -c 'mkdir -p "$HOME"; source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/provisioning.sh"; archive_members_safe "$1" tar.gz aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  _ "$TEST_ROOT/tool.tar.gz" >/dev/null 2>&1
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'unexpected archive inventory was accepted'
pass

# Locked archives may contain relative symlinks, but extracted links cannot escape the install root.
symlink_archive_root="$TEST_ROOT/symlink-archive"
mkdir -p "$symlink_archive_root/bin" "$symlink_archive_root/lib"
printf '#!/usr/bin/env bash\nexit 0\n' > "$symlink_archive_root/lib/tool"
ln -s ../lib/tool "$symlink_archive_root/bin/tool"
tar -czf "$TEST_ROOT/symlink-tool.tar.gz" -C "$symlink_archive_root" bin lib
symlink_inventory="$(tar -tzf "$TEST_ROOT/symlink-tool.tar.gz" | sha256sum)"
symlink_inventory="${symlink_inventory%% *}"
HOME="$TEST_ROOT/archive-home" TARGET_ROOT="$TEST_ROOT/archive-home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage5-test \
  bash -c 'source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/provisioning.sh"; archive_members_safe "$1" tar.gz "$2"' \
  _ "$TEST_ROOT/symlink-tool.tar.gz" "$symlink_inventory" || fail 'safe archived symlink was rejected'
ln -s /tmp "$symlink_archive_root/escape"
set +e
HOME="$TEST_ROOT/archive-home" TARGET_ROOT="$TEST_ROOT/archive-home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage5-test \
  bash -c 'source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/provisioning.sh"; extracted_links_safe "$1"' \
  _ "$symlink_archive_root" >/dev/null 2>&1
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'symlink escaping an extracted root was accepted'
pass

# Missing dependencies fail only their owning area; an unrelated selected area still applies.
isolation_repo="$TEST_ROOT/isolation-repo"
mkdir "$isolation_repo"
cp -a "$fixture/." "$isolation_repo/"
sed -i 's/^area|bash|framework$/area|bash|ready/' "$isolation_repo/manifests/areas.tsv"
# Keep this dependency-isolation fixture deterministic on workstations that now
# have every later Bash dependency installed.
sed -i 's/|bash|apply,check|generic,wsl|fzf|/|bash|apply,check|generic,wsl|stage5-missing-command|/' \
  "$isolation_repo/manifests/dependencies.tsv"
isolation_home="$(new_home isolation)"
set +e
TEST_OUTPUT="$(HOME="$isolation_home" PATH="$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
  DOTFILES_TEST_HOST_ROOT="$host" GIT_USER_NAME='Stage Five User' GIT_USER_EMAIL='stage5@example.com' \
  "$isolation_repo/bootstrap.sh" --area bash --area git 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'missing Bash dependencies did not fail the aggregate operation'
assert_contains "$TEST_OUTPUT" 'install packages with:'
[[ -f "$isolation_home/.local/state/dotfiles/v1/git.json" ]] || fail 'missing Bash dependency blocked the unrelated Git area'
[[ ! -e "$isolation_home/.local/state/dotfiles/v1/bash.json" ]] || fail 'area with missing dependencies was applied'
pass

# Omarchy core and Neovim drift are independent warnings; malformed/native-owner failures block.
omarchy_home="$(new_home omarchy)"
mkdir -p "$omarchy_home/.local/share/omarchy/bin" "$TEST_ROOT/omarchy-bin"
printf 'v3.8.2\n' > "$omarchy_home/.local/share/omarchy/version"
printf '#!/usr/bin/env bash\nexit 0\n' > "$omarchy_home/.local/share/omarchy/bin/omarchy-version"
printf '#!/usr/bin/env bash\nprintf "NVIM v0.12.4\\n"\n' > "$TEST_ROOT/omarchy-bin/nvim"
cat > "$TEST_ROOT/omarchy-bin/pacman" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == -Qo ]]; then
  printf '%s is owned by omarchy-nvim 2026.6.18-1\n' "$2"
elif [[ "$1" == -Q && "$2" == omarchy-nvim ]]; then
  printf 'omarchy-nvim 2026.6.18-1\n'
else
  exit 1
fi
SCRIPT
chmod +x "$omarchy_home/.local/share/omarchy/bin/omarchy-version" "$TEST_ROOT/omarchy-bin/nvim" "$TEST_ROOT/omarchy-bin/pacman"
set +e
TEST_OUTPUT="$(HOME="$omarchy_home" TARGET_ROOT="$omarchy_home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage5-test \
  SELECTED_PROFILE=omarchy PATH="$TEST_ROOT/omarchy-bin:/usr/bin:/bin" bash -c \
  'source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/provisioning.sh"; check_omarchy_core_drift; check_omarchy_neovim_drift' 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 0)) || fail 'parseable Omarchy drift became blocking'
assert_contains "$TEST_OUTPUT" 'warning: Omarchy core version drift'
assert_contains "$TEST_OUTPUT" 'warning: omarchy-nvim package drift'
printf 'malformed\nextra\n' > "$omarchy_home/.local/share/omarchy/version"
set +e
TEST_OUTPUT="$(HOME="$omarchy_home" TARGET_ROOT="$omarchy_home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=stage5-test \
  SELECTED_PROFILE=omarchy PATH="$TEST_ROOT/omarchy-bin:/usr/bin:/bin" bash -c \
  'source "$DOTFILES_DIR/lib/common.sh"; source "$DOTFILES_DIR/lib/engine.sh"; source "$DOTFILES_DIR/lib/provisioning.sh"; check_omarchy_core_drift' 2>&1)"
TEST_RC=$?
set -e
((TEST_RC == 1)) || fail 'malformed Omarchy core metadata was accepted'
assert_contains "$TEST_OUTPUT" 'malformed Omarchy core version metadata'
pass

printf 'PASS: %d Stage 5 ownership-aware provisioning test groups\n' "$TEST_COUNT"
