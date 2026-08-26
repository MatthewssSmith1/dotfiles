#!/usr/bin/env bash
# Native Herdr validation and Ubuntu lean package-only lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
export FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
: > "$FAKE_STOW_TRACE"

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
    [[ -f "\$config" ]] && grep -qxF 'prefix = "ctrl+space"' "\$config"
    ;;
  *) exit 2 ;;
esac
SCRIPT
  chmod 0755 "$path"
}

run_herdr_area() {
  local home="$1" host="$2" profile="$3" operation="$4" path_prefix="$5"
  HOME="$home" TARGET_ROOT="$home" DOTFILES_DIR="$REPO_DIR" SCRIPT_NAME=herdr-test \
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

reference="$REPO_DIR/packages/upstream/reference/omarchy/config/herdr/config.toml"
ubuntu_config="$REPO_DIR/packages/ubuntu/herdr/.config/herdr/config.toml"
helper="$REPO_DIR/packages/ubuntu/herdr/.config/dotfiles/bash/fns/herdr"
selector="$REPO_DIR/packages/ubuntu/herdr/.config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml"
cmp -s "$reference" "$ubuntu_config" || fail 'Ubuntu config is not the accepted v4 snapshot'
grep -qxF '"aqua:herdrdev/herdr" = "0.8.2"' "$selector" || fail 'Herdr selector is not exact'
bash -n "$helper" || fail 'Herdr helpers have invalid Bash syntax'
for function_name in hdl hds hdlm hsl; do
  grep -q "^${function_name}()" "$helper" || fail "missing Herdr helper: $function_name"
done
grep -qxF 'herdr validation-only' "$REPO_DIR/profiles/omarchy.conf" || fail 'native Herdr is not validation-only'
grep -qxF 'herdr ubuntu/herdr' "$REPO_DIR/profiles/ubuntu.conf" || fail 'Ubuntu Herdr closure is not final'
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
for operation in apply check remove; do
  trace_before="$(sha256sum "$FAKE_STOW_TRACE")"
  run_herdr_area "$native_home" "$native_host" omarchy "$operation" "$native_host/usr/bin" >/dev/null
  diff --no-dereference -r "$native_home" "$TEST_ROOT/native-before" >/dev/null ||
    fail "native Herdr $operation mutated HOME"
  [[ "$trace_before" == "$(sha256sum "$FAKE_STOW_TRACE")" ]] || fail "native Herdr $operation invoked Stow"
done
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
ubuntu_runtime="$TEST_ROOT/ubuntu-runtime"
make_herdr_runtime "$ubuntu_runtime/herdr"
ubuntu_home="$(new_home ubuntu)"
mkdir -p "$ubuntu_home/.config/herdr" "$ubuntu_home/.local/share/herdr"
printf 'session\n' > "$ubuntu_home/.config/herdr/session.json"
printf 'socket\n' > "$ubuntu_home/.local/share/herdr/socket"
cp -a "$ubuntu_home" "$TEST_ROOT/ubuntu-check-before"
set +e
run_herdr_area "$ubuntu_home" '' ubuntu check "$ubuntu_runtime" >/dev/null 2>&1
status=$?
set -e
((status != 0)) || fail 'unapplied Ubuntu Herdr check converged'
diff --no-dereference -r "$ubuntu_home" "$TEST_ROOT/ubuntu-check-before" >/dev/null || fail 'Ubuntu Herdr check mutated HOME'
run_herdr_area "$ubuntu_home" '' ubuntu apply "$ubuntu_runtime" >/dev/null
for path in .config/herdr/config.toml .config/dotfiles/bash/fns/herdr .config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml; do
  [[ -L "$ubuntu_home/$path" ]] || fail "Ubuntu Herdr omitted package link: $path"
done
cmp -s "$ubuntu_home/.config/herdr/config.toml" "$reference" || fail 'deployed Herdr config bytes changed'
[[ ! -e "$ubuntu_home/.local/state/dotfiles/v2/herdr.json" ]] || fail 'package-only Herdr wrote v2 state'
cp -a "$ubuntu_home" "$TEST_ROOT/ubuntu-applied"
run_herdr_area "$ubuntu_home" '' ubuntu check "$ubuntu_runtime" >/dev/null
diff --no-dereference -r "$ubuntu_home" "$TEST_ROOT/ubuntu-applied" >/dev/null || fail 'converged Herdr check mutated HOME'
run_herdr_area "$ubuntu_home" '' ubuntu remove "$ubuntu_runtime" >/dev/null
[[ ! -e "$ubuntu_home/.config/herdr/config.toml" && ! -e "$ubuntu_home/.config/dotfiles/bash/fns/herdr" &&
  ! -e "$ubuntu_home/.config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml" ]] || fail 'Herdr removal retained managed links'
[[ "$(< "$ubuntu_home/.config/herdr/session.json")" == session &&
  "$(< "$ubuntu_home/.local/share/herdr/socket")" == socket ]] || fail 'Herdr lifecycle changed runtime siblings'
run_herdr_area "$ubuntu_home" '' ubuntu remove "$TEST_ROOT/runtime-absent" >/dev/null
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
