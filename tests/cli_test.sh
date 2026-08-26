#!/usr/bin/env bash
# Public dotfiles grammar, non-mutating discovery, and relocatable launcher.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

ubuntu="$(make_host cli-ubuntu linux ubuntu 24.04)"
unsupported="$(make_host cli-unsupported linux debian 13)"
home="$(new_home cli)"

run_raw() {
  local stdout="$TEST_ROOT/stdout" stderr="$TEST_ROOT/stderr"
  set +e
  HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$unsupported" \
    "$DOTFILES" "$@" >"$stdout" 2>"$stderr"
  TEST_RC=$?
  set -e
  TEST_OUTPUT="$(< "$stdout")"
  TEST_ERROR="$(< "$stderr")"
}

# Help is successful on an unsupported host and never requires a usable HOME.
for args in '--help' 'help' 'help apply' 'help check' 'help remove' 'help list' 'help help'; do
  read -r -a words <<< "$args"
  HOME="$TEST_ROOT/missing-home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$unsupported" \
    "$DOTFILES" "${words[@]}" > "$TEST_ROOT/help.out" 2> "$TEST_ROOT/help.err" || fail "help failed: $args"
  [[ -s "$TEST_ROOT/help.out" && ! -s "$TEST_ROOT/help.err" ]] || fail "help did not use stdout: $args"
done
pass

# An operation is mandatory, and retired selectors/flags and malformed ordering
# fail before any deployment mutation.
invalid_commands=(
  ''
  'tools'
  '--check'
  '--remove'
  'apply --area tools'
  'apply --tool tools'
  'apply tools,agents'
  'apply tools --profile ubuntu'
  'apply tools --help'
  'remove --profile ubuntu tools'
  'check --profile=ubuntu tools'
  'list tools'
  'help unknown'
)
for args in "${invalid_commands[@]}"; do
  read -r -a words <<< "$args"
  run_raw "${words[@]}"
  ((TEST_RC != 0)) || fail "invalid command succeeded: ${args:-<empty>}"
done
assert_empty_home "$home"
pass

# Positional areas retain first-seen order and duplicates do not run twice.
fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
export FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
: > "$FAKE_STOW_TRACE"
CAPTURE_PATH_PREFIX="$fake_bin"
expect_success "$home" "$ubuntu" "$DOTFILES" apply tools agents tools
mapfile -t actual_packages < <(grep '^stow|false|' "$FAKE_STOW_TRACE" | cut -d'|' -f3)
[[ "${actual_packages[*]}" == 'tools tools agents' ]] || \
  fail "area order/de-duplication changed: ${actual_packages[*]}"
pass

# List is canonical, deterministic, and ignores state, locks, and dependencies.
list_home="$(new_home list)"
mkdir -p "$list_home/.local/state/dotfiles/v2"
printf 'not json\n' > "$list_home/.local/state/dotfiles/v2/git.json"
printf 'held\n' > "$list_home/.local/state/dotfiles/deploy.lock"
HOME="$list_home" PATH=/usr/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$unsupported" \
  "$DOTFILES" list > "$TEST_ROOT/list.out"
expected=$'profiles:\n  omarchy\n  ubuntu\nareas:\n  git ready\n  tools ready\n  bash ready\n  tmux ready\n  nvim ready\n  agents ready\n  herdr ready\n  desktop ready'
[[ "$(< "$TEST_ROOT/list.out")" == "$expected" ]] || fail 'unsupported-host list output changed'
HOME="$list_home" PATH=/usr/bin DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$ubuntu" \
  "$DOTFILES" list > "$TEST_ROOT/list-selected.out"
[[ "$(< "$TEST_ROOT/list-selected.out")" == "$expected"$'\nselected-profile: ubuntu' ]] || \
  fail 'supported-host list output changed'
[[ "$(< "$list_home/.local/state/dotfiles/v2/git.json")" == 'not json' ]] || fail 'list loaded or changed state'
[[ "$(< "$list_home/.local/state/dotfiles/deploy.lock")" == held ]] || fail 'list acquired or changed the lock'
pass

# The launcher follows its Stow link, survives relocation, forwards exact args,
# preserves status, and rejects missing or ambiguous checkout roots.
make_launcher_root() {
  local root="$1"
  mkdir -p "$root/manifests" "$root/profiles" "$root/packages/common/tools/.local/bin"
  : > "$root/manifests/areas.tsv"
  : > "$root/profiles/omarchy.conf"
  : > "$root/profiles/ubuntu.conf"
  cp "$REPO_DIR/packages/common/tools/.local/bin/dotfiles" "$root/packages/common/tools/.local/bin/dotfiles"
  chmod 0755 "$root/packages/common/tools/.local/bin/dotfiles"
}

moved="$TEST_ROOT/moved-checkout"
make_launcher_root "$moved"
cat > "$moved/dotfiles.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
exit 37
SCRIPT
chmod 0755 "$moved/dotfiles.sh"
mkdir "$TEST_ROOT/launcher-bin"
ln -s "$moved/packages/common/tools/.local/bin/dotfiles" "$TEST_ROOT/launcher-bin/dotfiles"
set +e
launcher_output="$("$TEST_ROOT/launcher-bin/dotfiles" check 'two words' --literal 2>&1)"
launcher_status=$?
set -e
((launcher_status == 37)) || fail "launcher changed exit status: $launcher_status"
[[ "$launcher_output" == $'<check>\n<two words>\n<--literal>' ]] || fail 'launcher changed arguments'

rm "$moved/profiles/ubuntu.conf"
if "$TEST_ROOT/launcher-bin/dotfiles" help > /dev/null 2>&1; then fail 'launcher accepted a missing root'; fi

outer="$TEST_ROOT/outer-root"
inner="$outer/inner-root"
make_launcher_root "$outer"
make_launcher_root "$inner"
printf '#!/usr/bin/env bash\nexit 0\n' > "$outer/dotfiles.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$inner/dotfiles.sh"
chmod 0755 "$outer/dotfiles.sh" "$inner/dotfiles.sh"
ln -s "$inner/packages/common/tools/.local/bin/dotfiles" "$TEST_ROOT/launcher-bin/ambiguous"
if "$TEST_ROOT/launcher-bin/ambiguous" help > /dev/null 2>&1; then fail 'launcher accepted ambiguous roots'; fi
pass

printf 'PASS: %s CLI test groups\n' "$TEST_COUNT"
