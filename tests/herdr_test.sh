#!/usr/bin/env bash
# Native Herdr validation and Ubuntu lean package-only lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
install_fake_stow "$fake_bin"

make_herdr_runtime() {
  local path="$1" version="${2:-0.8.2}"
  mkdir -p "${path%/*}"
  cat > "$path" <<SCRIPT
#!/usr/bin/env bash
case "\${1:-}" in
  --version) printf 'herdr $version\\n' ;;
  config)
    [[ "\${2:-}" == check ]] || exit 2
    config="\${XDG_CONFIG_HOME:-\$HOME/.config}/herdr/config.toml"
    [[ -f "\$config" ]] && grep -qxF 'prefix = "ctrl+space"' "\$config" || exit 1
    [[ -z "\${HERDR_CONFIG_TRACE:-}" ]] || sha256sum "\$config" | cut -d ' ' -f1 >> "\$HERDR_CONFIG_TRACE"
    ;;
  *) exit 2 ;;
esac
SCRIPT
  chmod 0755 "$path"
}

run_herdr_area() {
  local home="$1" host="$2" profile="$3" operation="$4" path_prefix="$5" repo="${6:-$REPO_DIR}"
  HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$repo" SCRIPT_NAME=herdr-test \
    SELECTED_PROFILE="$profile" MODE="$operation" HOST_ROOT="$host" \
    PATH="$path_prefix:$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 bash -c '
      set -Eeuo pipefail
      source "$DOTFILES_DIR/lib/common.sh"
      source "$DOTFILES_DIR/lib/host.sh"
      source "$DOTFILES_DIR/lib/lean_engine.sh"
      source "$DOTFILES_DIR/lib/areas/herdr.sh"
      validate_area_manifest
      case "$MODE" in
        apply) preflight_herdr; apply_herdr ;;
        check) preflight_herdr ;;
        remove) remove_herdr ;;
      esac
    '
}

make_herdr_repo_fixture() {
  local fixture="$1"
  mkdir -p "$fixture"
  ln -s "$REPO_DIR/lib" "$fixture/lib"
  ln -s "$REPO_DIR/manifests" "$fixture/manifests"
  ln -s "$REPO_DIR/profiles" "$fixture/profiles"
  cp -a "$REPO_DIR/packages" "$fixture/packages"
}

reference="$REPO_DIR/packages/upstream/reference/omarchy/config/herdr/config.toml"
ubuntu_config="$REPO_DIR/packages/ubuntu/herdr/.config/herdr/config.toml"
helper="$REPO_DIR/packages/ubuntu/herdr/.config/dotfiles/bash/fns/herdr"
selector="$REPO_DIR/packages/ubuntu/herdr/.config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml"
path_dropin="$REPO_DIR/packages/ubuntu/herdr/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf"
herdr_preamble=$'onboarding = false\n\n[update]\nversion_check = false\nmanifest_check = true\n\n'
path_dropin_content=$'[Service]\nEnvironment=PATH=%h/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin\n'
expected_config="$TEST_ROOT/herdr-ubuntu-expected.toml"
expected_path_dropin="$TEST_ROOT/moshi-herdr-path-expected.conf"
{ printf '%s' "$herdr_preamble"; cat "$reference"; } > "$expected_config"
printf '%s' "$path_dropin_content" > "$expected_path_dropin"
cmp -s "$expected_config" "$ubuntu_config" || fail 'Ubuntu config is not the exact policy derivation'
cmp -s "$expected_path_dropin" "$path_dropin" || fail 'Moshi PATH drop-in bytes are not exact'
grep -qxF '"aqua:ogulcancelik/herdr" = "0.8.2"' "$selector" || fail 'Herdr selector is not exact'
bash -n "$helper" || fail 'Herdr helpers have invalid Bash syntax'
for function_name in hdl hds hdlm hsl; do
  grep -q "^${function_name}()" "$helper" || fail "missing Herdr helper: $function_name"
done
grep -qxF 'herdr validation-only' "$REPO_DIR/profiles/omarchy.conf" || fail 'native Herdr is not validation-only'
grep -qxF 'herdr ubuntu/herdr' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu Herdr closure is not final'
pass

# Every malformed policy derivation is rejected before mutation.
for mutation in missing altered duplicated reordered extra; do
  fixture="$TEST_ROOT/repo-$mutation"
  make_herdr_repo_fixture "$fixture"
  malformed="$fixture/packages/ubuntu/herdr/.config/herdr/config.toml"
  case "$mutation" in
    missing) cp "$reference" "$malformed" ;;
    altered) { printf '%s' "${herdr_preamble/version_check = false/version_check = true}"; cat "$reference"; } > "$malformed" ;;
    duplicated) { printf '%s%s' "$herdr_preamble" "$herdr_preamble"; cat "$reference"; } > "$malformed" ;;
    reordered) { printf 'onboarding = false\n\n[update]\nmanifest_check = true\nversion_check = false\n\n'; cat "$reference"; } > "$malformed" ;;
    extra) { printf '%s' "$herdr_preamble"; printf '# extra policy bytes\n'; cat "$reference"; } > "$malformed" ;;
  esac
  malformed_home="$(new_home "malformed-$mutation")"
  mkdir -p "$malformed_home/.config/herdr"
  printf 'session\n' > "$malformed_home/.config/herdr/session.json"
  set +e
  output="$(run_herdr_area "$malformed_home" '' ubuntu apply "$TEST_ROOT/runtime-absent" "$fixture" 2>&1)"
  status=$?
  set -e
  ((status != 0)) || fail "$mutation Herdr policy derivation was accepted"
  assert_contains "$output" 'exact policy preamble plus accepted v4 snapshot'
  [[ "$(< "$malformed_home/.config/herdr/session.json")" == session ]] || fail "$mutation derivation refusal mutated HOME"
  [[ ! -e "$malformed_home/.local/state/dotfiles/v2/herdr.json" ]] || fail "$mutation derivation refusal wrote state"
done
pass

# The area validator, not only this test's static assertion, rejects drop-in drift.
fixture="$TEST_ROOT/repo-dropin-drift"
make_herdr_repo_fixture "$fixture"
printf '%s# drift\n' "$path_dropin_content" > \
  "$fixture/packages/ubuntu/herdr/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf"
malformed_home="$(new_home dropin-drift)"
set +e
output="$(run_herdr_area "$malformed_home" '' ubuntu apply "$TEST_ROOT/runtime-absent" "$fixture" 2>&1)"
status=$?
set -e
((status != 0)) || fail 'mutated Moshi PATH drop-in passed area validation'
assert_contains "$output" 'Moshi Herdr PATH drop-in bytes are not exact'
assert_empty_home "$malformed_home"
pass

# Native apply, check, and remove validate exact package-owned stock behavior
# without invoking Stow or creating either deployment-state generation.
native_host="$(make_system_fixture native-herdr)"
make_herdr_runtime "$native_host/usr/bin/herdr"
record_pacman_ownership "$native_host" 'herdr 0.8.2-1' /usr/bin/herdr
native_home="$(new_home native)"
mkdir -p "$native_home/.config/herdr"
cp "$reference" "$native_home/.config/herdr/config.toml"
chmod 0644 "$native_home/.config/herdr/config.toml"
printf 'session\n' > "$native_home/.config/herdr/session.json"
cp -a "$native_home" "$TEST_ROOT/native-before"
export HERDR_CONFIG_TRACE="$TEST_ROOT/native-config.trace"
: > "$HERDR_CONFIG_TRACE"
for operation in apply check remove; do
  trace_before="$(sha256sum "$FAKE_STOW_TRACE")"
  run_herdr_area "$native_home" "$native_host" omarchy "$operation" "$native_host/usr/bin" >/dev/null
  diff --no-dereference -r "$native_home" "$TEST_ROOT/native-before" >/dev/null ||
    fail "native Herdr $operation mutated HOME"
  [[ "$trace_before" == "$(sha256sum "$FAKE_STOW_TRACE")" ]] || fail "native Herdr $operation invoked Stow"
done
native_hash="$(sha256sum "$reference" | cut -d ' ' -f1)"
[[ "$(sort -u "$HERDR_CONFIG_TRACE")" == "$native_hash" ]] || fail 'native syntax check did not use the immutable reference'
unset HERDR_CONFIG_TRACE
[[ ! -e "$native_home/.local/state/dotfiles/v1/herdr.json" &&
  ! -e "$native_home/.local/state/dotfiles/v2/herdr.json" ]] || fail 'native Herdr created deployment state'
pass

# Native drift, wrong package identity, and PATH shadows refuse with restoration guidance.
printf '# drift\n' >> "$native_home/.config/herdr/config.toml"
set +e
output="$(run_herdr_area "$native_home" "$native_host" omarchy check "$native_host/usr/bin" 2>&1)"
status=$?
set -e
((status != 0)) || fail 'native config drift was accepted'
assert_contains "$output" 'omarchy refresh herdr or reinstall Herdr'
cp "$reference" "$native_home/.config/herdr/config.toml"
shadow="$TEST_ROOT/shadow"
make_herdr_runtime "$shadow/herdr"
set +e
output="$(run_herdr_area "$native_home" "$native_host" omarchy check "$shadow:$native_host/usr/bin" 2>&1)"
status=$?
set -e
((status != 0)) || fail 'native PATH shadow was accepted'
assert_contains "$output" 'package-owned /usr/bin/herdr'
printf '/usr/bin/herdr\therdr 0.8.1\n' > "$native_host/var/lib/dotfiles-test/pacman-owners.tsv"
set +e
output="$(run_herdr_area "$native_home" "$native_host" omarchy check "$native_host/usr/bin" 2>&1)"
status=$?
set -e
((status != 0)) || fail 'wrong native package version was accepted'
assert_contains "$output" "herdr 0.8.2-1"
pass

# Ubuntu deploys only exact Stow links, creates no state, validates syntax with
# the selected runtime, and leaves application-owned siblings untouched.
ubuntu_home="$(new_home ubuntu)"
ubuntu_runtime="$ubuntu_home/.local/share/mise/installs/aqua-ogulcancelik-herdr/0.8.2"
make_herdr_runtime "$ubuntu_runtime/herdr"
mkdir -p "$ubuntu_home/.config/herdr" "$ubuntu_home/.config/systemd/user" "$ubuntu_home/.local/share/herdr"
printf 'session\n' > "$ubuntu_home/.config/herdr/session.json"
printf 'generated primary service\n' > "$ubuntu_home/.config/systemd/user/moshi-hook.service"
printf 'log\n' > "$ubuntu_home/.local/share/herdr/herdr.log"
printf 'socket\n' > "$ubuntu_home/.local/share/herdr/socket"
cp -a "$ubuntu_home" "$TEST_ROOT/ubuntu-check-before"
export HERDR_CONFIG_TRACE="$TEST_ROOT/ubuntu-config.trace"
: > "$HERDR_CONFIG_TRACE"
set +e
run_herdr_area "$ubuntu_home" '' ubuntu check "$ubuntu_runtime" >/dev/null 2>&1
status=$?
set -e
((status != 0)) || fail 'unapplied Ubuntu Herdr check converged'
diff --no-dereference -r "$ubuntu_home" "$TEST_ROOT/ubuntu-check-before" >/dev/null || fail 'Ubuntu Herdr check mutated HOME'
run_herdr_area "$ubuntu_home" '' ubuntu apply "$ubuntu_runtime" >/dev/null
for path in .config/herdr/config.toml .config/dotfiles/bash/fns/herdr .config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml .config/systemd/user/moshi-hook.service.d/10-herdr-path.conf; do
  [[ -L "$ubuntu_home/$path" ]] || fail "Ubuntu Herdr omitted package link: $path"
done
cmp -s "$ubuntu_home/.config/herdr/config.toml" "$ubuntu_config" || fail 'deployed Herdr config bytes changed'
cmp -s "$ubuntu_home/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf" "$path_dropin" || fail 'deployed Moshi PATH drop-in bytes changed'
[[ ! -L "$ubuntu_home/.config/systemd/user/moshi-hook.service" &&
  "$(< "$ubuntu_home/.config/systemd/user/moshi-hook.service")" == 'generated primary service' ]] || fail 'Herdr owned Moshi primary service'
[[ ! -e "$ubuntu_home/.local/state/dotfiles/v2/herdr.json" ]] || fail 'package-only Herdr wrote v2 state'
cp -a "$ubuntu_home" "$TEST_ROOT/ubuntu-applied"
run_herdr_area "$ubuntu_home" '' ubuntu apply "$ubuntu_runtime" >/dev/null
diff --no-dereference -r "$ubuntu_home" "$TEST_ROOT/ubuntu-applied" >/dev/null || fail 'converged Herdr apply mutated HOME'
run_herdr_area "$ubuntu_home" '' ubuntu check "$ubuntu_runtime" >/dev/null
ubuntu_hash="$(sha256sum "$ubuntu_config" | cut -d ' ' -f1)"
[[ "$(sort -u "$HERDR_CONFIG_TRACE")" == "$ubuntu_hash" ]] || fail 'Ubuntu syntax check did not use the derived payload'
unset HERDR_CONFIG_TRACE
diff --no-dereference -r "$ubuntu_home" "$TEST_ROOT/ubuntu-applied" >/dev/null || fail 'converged Herdr check mutated HOME'
run_herdr_area "$ubuntu_home" '' ubuntu remove "$ubuntu_runtime" >/dev/null
[[ ! -e "$ubuntu_home/.config/herdr/config.toml" && ! -e "$ubuntu_home/.config/dotfiles/bash/fns/herdr" &&
  ! -e "$ubuntu_home/.config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml" &&
  ! -e "$ubuntu_home/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf" ]] || fail 'Herdr removal retained managed links'
[[ "$(< "$ubuntu_home/.config/herdr/session.json")" == session &&
  "$(< "$ubuntu_home/.config/systemd/user/moshi-hook.service")" == 'generated primary service' &&
  "$(< "$ubuntu_home/.local/share/herdr/herdr.log")" == log &&
  "$(< "$ubuntu_home/.local/share/herdr/socket")" == socket ]] || fail 'Herdr lifecycle changed runtime siblings'
run_herdr_area "$ubuntu_home" '' ubuntu remove "$TEST_ROOT/runtime-absent" >/dev/null
pass

# A pre-existing Moshi PATH drop-in refuses deployment without touching it.
collision_home="$(new_home dropin-collision)"
collision_runtime="$collision_home/.local/share/mise/installs/aqua-ogulcancelik-herdr/0.8.2"
make_herdr_runtime "$collision_runtime/herdr"
mkdir -p "$collision_home/.config/systemd/user/moshi-hook.service.d"
printf 'host-owned\n' > "$collision_home/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf"
set +e
run_herdr_area "$collision_home" '' ubuntu apply "$collision_runtime" >/dev/null 2>&1
status=$?
set -e
((status != 0)) || fail 'existing Moshi PATH drop-in was replaced'
[[ "$(< "$collision_home/.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf")" == host-owned ]] ||
  fail 'Moshi PATH drop-in collision refusal mutated destination'
[[ ! -e "$collision_home/.config/herdr/config.toml" ]] || fail 'Moshi PATH drop-in collision partially deployed Herdr'
pass

# A stale installation cannot satisfy the Ubuntu contract by reporting the
# selected version from a differently owned path.
stale_home="$(new_home stale-runtime)"
stale_runtime="$stale_home/.local/share/mise/installs/aqua-ogulcancelik-herdr/0.7.5"
make_herdr_runtime "$stale_runtime/herdr"
set +e
output="$(run_herdr_area "$stale_home" '' ubuntu check "$stale_runtime" 2>&1)"
status=$?
set -e
((status != 0)) || fail 'stale Herdr runtime path was accepted'
assert_contains "$output" "aqua-ogulcancelik-herdr/0.8.2/herdr"
pass

# Modified destinations and legacy v1 ownership refuse without mutation.
run_herdr_area "$ubuntu_home" '' ubuntu apply "$ubuntu_runtime" >/dev/null
rm "$ubuntu_home/.config/herdr/config.toml"
printf 'unrelated\n' > "$ubuntu_home/.config/herdr/config.toml"
before="$(sha256sum "$ubuntu_home/.config/herdr/config.toml")"
set +e
run_herdr_area "$ubuntu_home" '' ubuntu remove "$ubuntu_runtime" >/dev/null 2>&1
status=$?
set -e
((status != 0)) || fail 'modified Herdr destination was removed'
[[ "$before" == "$(sha256sum "$ubuntu_home/.config/herdr/config.toml")" ]] || fail 'Herdr conflict refusal mutated the destination'
legacy_home="$(new_home legacy)"
mkdir -p "$legacy_home/.local/state/dotfiles/v1"
printf '{}\n' > "$legacy_home/.local/state/dotfiles/v1/herdr.json"
set +e
output="$(run_herdr_area "$legacy_home" '' ubuntu apply "$ubuntu_runtime" 2>&1)"
status=$?
set -e
((status != 0)) || fail 'legacy Herdr state was accepted'
assert_contains "$output" "legacy v1 deployment state exists for lean area 'herdr'"
pass

# Helpers are safe to source and name missing optional dependencies clearly.
output="$(PATH=/usr/bin:/bin bash -c 'source "$1"; declare -F hdl hds hdlm hsl >/dev/null; _herdr_require hunk' _ "$helper" 2>&1)" &&
  fail 'missing helper dependency unexpectedly passed'
assert_contains "$output" 'Herdr helper requires hunk'
pass

printf 'PASS: Herdr area checks (%d groups)\n' "$TEST_COUNT"
