#!/usr/bin/env bash
# Isolated runtime contracts for the guarded native Windows VM launcher.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

source_wrapper="$REPO_DIR/packages/omarchy/desktop/.local/bin/dotfiles-omarchy-windows-vm"
[[ -f "$source_wrapper" ]] || fail 'Windows VM wrapper payload is missing'

vm_root="$TEST_ROOT/vm"
vm_bin="$TEST_ROOT/bin"
vm_home="$TEST_ROOT/home"
native="$vm_root/usr/bin/omarchy-windows-vm"
wrapper="$vm_root/dotfiles-omarchy-windows-vm"
mkdir -p "$vm_bin" "$(dirname -- "$native")" "$vm_home"
sed "s|/usr/bin/omarchy-windows-vm|$native|g" "$source_wrapper" > "$wrapper"
chmod 0755 "$wrapper"

cat > "$native" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$VM_NATIVE_TRACE.args"
printf '%s\n' "${OMARCHY_WINDOWS_DIR-}" > "$VM_NATIVE_TRACE.env"
exit "${VM_NATIVE_STATUS:-0}"
SCRIPT
cat > "$vm_bin/notify-send" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "$@" >> "$VM_NOTIFY_TRACE"
SCRIPT
cat > "$vm_bin/getent" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${VM_GETENT_FAIL:-0}" == 1 ]]; then exit 2; fi
printf 'tester:x:%s:%s::%s:/bin/bash\n' "$EUID" "$(id -g)" "${VM_PASSWD_HOME:-$HOME}"
SCRIPT
cat > "$vm_bin/find" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${VM_FIND_FAIL:-0}" == 1 ]]; then exit 2; fi
exec /usr/bin/find "$@"
SCRIPT
cat > "$vm_bin/chmod" <<'SCRIPT'
#!/usr/bin/env bash
if [[ ${VM_CHMOD_FAIL:-0} == 1 ]]; then exit 2; fi
printf '%s\0' "$@" >> "$VM_CHMOD_TRACE"
realpath -e -- "${*: -1}" > "$VM_CHMOD_TARGET"
exec /usr/bin/chmod "$@"
SCRIPT
cat > "$vm_bin/stat" <<'SCRIPT'
#!/usr/bin/env bash
path="${*: -1}"
printf '%s\n' "$*" >> "$VM_STAT_TRACE"
if [[ -n "${VM_BAD_OWNER_PATH:-}" && "$path" == "$VM_BAD_OWNER_PATH" ]]; then
  case " $* " in
    *' %u '*) printf '%s\n' "$((EUID + 1))" ;;
    *) exec /usr/bin/stat "$@" ;;
  esac
  exit 0
fi
if [[ -n "${VM_BAD_MODE_PATH:-}" && "$path" == "$VM_BAD_MODE_PATH" ]]; then
  case " $* " in
    *' %a '*) printf '777\n' ;;
    *) exec /usr/bin/stat "$@" ;;
  esac
  exit 0
fi
case " $* " in
  *' %u '*) printf '0\n' ;;
  *' %a '*) printf '755\n' ;;
  *) exec /usr/bin/stat "$@" ;;
esac
SCRIPT
chmod 0755 "$native" "$vm_bin"/*

export VM_NATIVE_TRACE="$TEST_ROOT/native" VM_NOTIFY_TRACE="$TEST_ROOT/notify" VM_CHMOD_TRACE="$TEST_ROOT/chmod"
export VM_CHMOD_TARGET="$TEST_ROOT/chmod-target"
export VM_STAT_TRACE="$TEST_ROOT/stat"

reset_traces() {
  : > "$VM_NOTIFY_TRACE"
  : > "$VM_CHMOD_TRACE"
  : > "$VM_STAT_TRACE"
  rm -f -- "$VM_NATIVE_TRACE.args" "$VM_NATIVE_TRACE.env" "$VM_CHMOD_TARGET"
}

run_wrapper() {
  local output_file="$TEST_ROOT/wrapper.out" status
  reset_traces
  set +e
  HOME="$vm_home" PATH="$vm_bin:/usr/bin:/bin" "$wrapper" "$@" >"$output_file" 2>&1
  status=$?
  set -e
  TEST_OUTPUT="$(< "$output_file")"
  TEST_RC=$status
}

assert_not_invoked() {
  [[ ! -e "$VM_NATIVE_TRACE.args" && ! -s "$VM_CHMOD_TRACE" ]] ||
    fail 'refusal invoked upstream or chmod'
}

prepare_normal() {
  rm -rf -- "$vm_home/.windows" "$vm_home/Windows"
  mkdir -p "$vm_home/.windows" "$vm_home/Windows/child"
  : > "$vm_home/.windows/windows.boot"
  chmod 2755 "$vm_home/.windows" "$vm_home/Windows" "$vm_home/Windows/child"
}

# Normal mode validates the marker first, forwards only fixed native arguments,
# and removes only the shared directory's setgid bit.
prepare_normal
storage_mode="$(stat -c %a "$vm_home/.windows")"
run_wrapper
((TEST_RC == 0)) || fail "normal wrapper launch failed: $TEST_OUTPUT; stat trace: $(< "$VM_STAT_TRACE")"
mapfile -d '' -t native_args < "$VM_NATIVE_TRACE.args"
[[ ${#native_args[@]} == 2 && "${native_args[0]}" == launch && "${native_args[1]}" == --keep-alive ]] || fail 'native VM arguments are not exact'
[[ "$(< "$VM_NATIVE_TRACE.env")" == '' ]] || fail 'default native storage environment was unexpectedly rewritten'
[[ "$(stat -c %a "$vm_home/.windows")" == "$storage_mode" &&
  "$(stat -c %a "$vm_home/Windows")" == 755 &&
  "$(stat -c %A "$vm_home/Windows/child")" == *s* ]] ||
  fail 'wrapper chmod was not shared-root-only and setgid-only'
mapfile -d '' -t chmod_args < "$VM_CHMOD_TRACE"
[[ "${#chmod_args[@]}" == 3 && "${chmod_args[0]}" == g-s && "${chmod_args[1]}" == -- &&
  "${chmod_args[2]}" == /proc/*/fd/* && "$(< "$VM_CHMOD_TARGET")" == "$vm_home/Windows" ]] ||
  fail 'shared chmod arguments are not exact or descriptor-pinned'
prepare_normal
OMARCHY_WINDOWS_DIR=/var/lib/omarchy/windows run_wrapper
((TEST_RC == 0)) || fail 'explicit default OMARCHY_WINDOWS_DIR was refused'
[[ "$(< "$VM_NATIVE_TRACE.env")" == /var/lib/omarchy/windows ]] || fail 'allowed storage environment was not preserved'
pass

# Missing or unsafe markers and all caller-controlled invocation variants fail
# before mutation. Environment overrides cannot redirect native storage or trust.
prepare_normal
rm "$vm_home/.windows/windows.boot"
run_wrapper
((TEST_RC != 0)) || fail 'normal mode accepted missing windows.boot'
assert_not_invoked
assert_contains "$TEST_OUTPUT" 'windows.boot'
[[ -s "$VM_NOTIFY_TRACE" ]] || fail 'marker refusal was not notified'
for bad_args in '--fresh-setup-once extra' '--unknown' 'launch --keep-alive'; do
  prepare_normal
  read -r -a argv <<< "$bad_args"
  run_wrapper "${argv[@]}"
  ((TEST_RC != 0)) || fail "wrapper accepted alternate invocation: $bad_args"
  assert_not_invoked
done
prepare_normal
reset_traces
set +e
HOME="$vm_home" PATH="$vm_bin:/usr/bin:/bin" OMARCHY_WINDOWS_DIR="$TEST_ROOT/alternate" \
  DOTFILES_TEST_NATIVE_VM="$TEST_ROOT/bypass" DOTFILES_TEST_NATIVE_OWNER="$EUID" \
  "$wrapper" >"$TEST_ROOT/override.out" 2>&1
override_status=$?
set -e
((override_status != 0)) || fail 'wrapper accepted a storage or test override'
assert_not_invoked
pass

# Fresh setup permits only absent or provably empty storage, including hidden
# entries, and never creates either user directory itself.
rm -rf -- "$vm_home/.windows" "$vm_home/Windows"
run_wrapper --fresh-setup-once
((TEST_RC == 0)) || fail "fresh absent storage failed: $TEST_OUTPUT"
[[ ! -e "$vm_home/.windows" && ! -e "$vm_home/Windows" ]] || fail 'fresh mode created user directories'
mkdir "$vm_home/.windows"
run_wrapper --fresh-setup-once
((TEST_RC == 0)) || fail 'fresh empty storage was refused'
run_wrapper
((TEST_RC != 0)) || fail 'fresh bypass persisted into a normal invocation'
assert_not_invoked
: > "$vm_home/.windows/data.img"
run_wrapper --fresh-setup-once
((TEST_RC != 0)) || fail 'fresh mode accepted an existing disk'
assert_not_invoked
rm "$vm_home/.windows/data.img"
: > "$vm_home/.windows/.hidden"
run_wrapper --fresh-setup-once
((TEST_RC != 0)) || fail 'fresh mode accepted hidden storage content'
assert_not_invoked
rm "$vm_home/.windows/.hidden"
VM_FIND_FAIL=1 run_wrapper --fresh-setup-once
((TEST_RC != 0)) || fail 'fresh mode accepted a failed emptiness proof'
assert_not_invoked
pass

# Owned directory symlinks are valid, but canonical overlap, wrong owners,
# unsafe HOME/account identity, and a symlink marker are refused before chmod.
storage_target="$TEST_ROOT/storage-target"
shared_target="$TEST_ROOT/shared-target"
rm -rf -- "$vm_home/.windows" "$vm_home/Windows" "$storage_target" "$shared_target"
mkdir "$storage_target" "$shared_target"
: > "$storage_target/windows.boot"
ln -s "$storage_target" "$vm_home/.windows"
ln -s "$shared_target" "$vm_home/Windows"
run_wrapper
((TEST_RC == 0)) || fail "legitimate directory symlinks were refused: $TEST_OUTPUT"
rm "$vm_home/Windows"
ln -s "$storage_target" "$vm_home/Windows"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted identical canonical storage and shared paths'
assert_not_invoked
rm "$vm_home/Windows"
mkdir "$storage_target/nested"
ln -s "$storage_target/nested" "$vm_home/Windows"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted nested canonical paths'
assert_not_invoked
rm "$vm_home/.windows" "$vm_home/Windows"
shared_parent="$TEST_ROOT/shared-parent"
mkdir -p "$shared_parent/nested"
: > "$shared_parent/nested/windows.boot"
ln -s "$shared_parent/nested" "$vm_home/.windows"
ln -s "$shared_parent" "$vm_home/Windows"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted reverse-nested canonical paths'
assert_not_invoked
rm "$vm_home/.windows" "$vm_home/Windows"
prepare_normal
rm -rf -- "$vm_home/Windows"
ln -s / "$vm_home/Windows"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a wrongly owned shared directory'
assert_not_invoked
prepare_normal
rm "$vm_home/.windows/windows.boot"
ln -s /dev/null "$vm_home/.windows/windows.boot"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a symlink windows.boot marker'
assert_not_invoked
VM_PASSWD_HOME="$TEST_ROOT/different-home" run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted HOME differing from the account database'
assert_not_invoked
VM_GETENT_FAIL=1 run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted an unverifiable account home'
assert_not_invoked
saved_home="$vm_home"
vm_home=relative-home
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a relative HOME'
assert_not_invoked
vm_home="$saved_home"
rm -rf -- "$vm_home/.windows" "$vm_home/Windows"
ln -s / "$vm_home/.windows"
run_wrapper --fresh-setup-once
((TEST_RC != 0)) || fail 'wrapper accepted wrongly owned storage'
assert_not_invoked
pass

# Broken links, ordinary files, unreadable directories, and mutation errors fail
# without calling the native launcher.
for relative in .windows Windows; do
  for kind in broken file unreadable; do
    prepare_normal
    rm -rf -- "$vm_home/$relative"
    case "$kind" in
      broken) ln -s "$TEST_ROOT/nonexistent" "$vm_home/$relative" ;;
      file) : > "$vm_home/$relative" ;;
      unreadable) mkdir "$vm_home/$relative"; chmod 000 "$vm_home/$relative" ;;
    esac
    run_wrapper --fresh-setup-once
    ((TEST_RC != 0)) || fail "wrapper accepted $kind $relative"
    assert_not_invoked
    if [[ $kind == unreadable ]]; then chmod 0700 "$vm_home/$relative"; fi
  done
done
prepare_normal
VM_CHMOD_FAIL=1 run_wrapper
((TEST_RC != 0)) || fail 'chmod failure was ignored'
[[ ! -e "$VM_NATIVE_TRACE.args" && -s "$VM_NOTIFY_TRACE" ]] || fail 'chmod failure invoked upstream or lacked notification'
pass

# Native trust failures precede chmod. Upstream failures retain their status and
# are notified, while a missing shared directory remains a valid normal launch.
prepare_normal
VM_BAD_OWNER_PATH="$native" run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a non-root-owned native executable'
assert_not_invoked
prepare_normal
VM_BAD_OWNER_PATH="$(dirname -- "$native")" run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a non-root-owned native ancestor'
assert_not_invoked
prepare_normal
VM_BAD_MODE_PATH="$(dirname -- "$native")" run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a writable native ancestor'
assert_not_invoked
prepare_normal
mv "$native" "$native.real"
ln -s "$native.real" "$native"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a symlink native executable'
assert_not_invoked
rm "$native"
mv "$native.real" "$native"
chmod 0644 "$native"
run_wrapper
((TEST_RC != 0)) || fail 'wrapper accepted a non-executable native launcher'
assert_not_invoked
chmod 0755 "$native"
prepare_normal
rm -rf -- "$vm_home/Windows"
run_wrapper
((TEST_RC == 0)) && [[ ! -s "$VM_CHMOD_TRACE" ]] || fail 'missing shared directory was not a no-op'
prepare_normal
VM_NATIVE_STATUS=37 run_wrapper
((TEST_RC == 37)) || fail 'wrapper did not preserve native failure status'
[[ -s "$VM_NOTIFY_TRACE" ]] || fail 'native failure was not notified'
assert_contains "$TEST_OUTPUT" 'Native Windows VM launch failed'
pass

printf 'PASS: %s Windows VM wrapper test groups\n' "$TEST_COUNT"
