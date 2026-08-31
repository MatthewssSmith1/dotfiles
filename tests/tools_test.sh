#!/usr/bin/env bash
# Lean tools/mise package policy, diagnostics, and lifecycle.

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

fake_bin="$TEST_ROOT/bin"
mkdir "$fake_bin"
cp "$REPO_DIR/tests/fixtures/fake-stow" "$fake_bin/stow"
chmod 0755 "$fake_bin/stow"
FAKE_STOW_TRACE="$TEST_ROOT/stow.trace"
export FAKE_STOW_TRACE
CAPTURE_PATH_PREFIX="$fake_bin"
: > "$FAKE_STOW_TRACE"
ubuntu="$(make_host tools-ubuntu linux ubuntu 24.04)"
native="$(make_host tools-native linux omarchy 4)"
mkdir -p "$native/usr/share/omarchy"
printf '4.0.0.alpha\n' > "$native/usr/share/omarchy/version"
printf '#!/usr/bin/env bash\nexit 0\n' > "$native/usr/bin/omarchy"
chmod 0755 "$native/usr/bin/omarchy"
record_pacman_ownership "$native" 'omarchy 4.0.1-1' /usr/share/omarchy/version /usr/bin/omarchy

make_tool() {
  local name="$1" output="$2"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$output" > "$fake_bin/$name"
  chmod 0755 "$fake_bin/$name"
}

# Apply is configuration-only even when mise and selected tools are absent.
home="$(new_home apply)"
expect_success "$home" "$ubuntu" "$DOTFILES" apply tools
[[ -L "$home/.config/mise/conf.d/20-dotfiles-tools.toml" && -L "$home/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml" ]] ||
  fail 'Ubuntu mise fragments were not deployed'
[[ ! -e "$home/.local/bin/dotfiles-omarchy-prune" &&
  ! -e "$home/.local/bin/dotfiles-omarchy-amdgpu-ips" ]] ||
  fail 'Ubuntu deployed an Omarchy administration command'
[[ ! -e "$home/.local/state/dotfiles/v2" ]] || fail 'package-only tools wrote ownership state'
[[ ! -e "$home/network-attempted" ]] || fail 'tools apply attempted installation'
pass

# Missing checks are offline and print every explicit selector/manual action.
export DOTFILES_TEST_HIDE_COMMANDS='mise node pnpm wt'
expect_failure 'mise is absent' "$home" "$ubuntu" "$DOTFILES" check tools
assert_contains "$TEST_OUTPUT" 'mise install node@lts'
assert_contains "$TEST_OUTPUT" 'mise install aqua:pnpm/pnpm@11.13.1'
assert_contains "$TEST_OUTPUT" 'mise install aqua:max-sixty/worktrunk@0.68.0'
unset DOTFILES_TEST_HIDE_COMMANDS
pass

# Selected fake tools satisfy the exact accepted checks.
make_tool mise 'mise 2026.7.7'
make_tool node 'v24.0.0'
make_tool pnpm '11.13.1'
make_tool wt 'worktrunk 0.68.0'
expect_success "$home" "$ubuntu" "$DOTFILES" check tools
pass

# Native tools deploy the shared launcher and native prune command without
# executing either payload. Removal converges from the detected profile.
cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/prune-unexpected.trace"
exit 99
SCRIPT
chmod 0755 "$fake_bin/omarchy"
native_home="$(new_home native)"
expect_success "$native_home" "$native" "$DOTFILES" apply tools
[[ -L "$native_home/.local/bin/dotfiles" && -L "$native_home/.local/bin/dotfiles-omarchy-prune" &&
  -L "$native_home/.local/bin/dotfiles-omarchy-amdgpu-ips" ]] ||
  fail 'native tools launchers were not deployed'
expect_success "$native_home" "$native" "$DOTFILES" check tools
expect_success "$native_home" "$native" "$DOTFILES" remove tools
[[ ! -e "$native_home/.local/bin/dotfiles" && ! -e "$native_home/.local/bin/dotfiles-omarchy-prune" &&
  ! -e "$native_home/.local/bin/dotfiles-omarchy-amdgpu-ips" ]] ||
  fail 'native tools removal retained launchers'
expect_success "$native_home" "$native" "$DOTFILES" remove tools
[[ ! -e "$native_home/prune-unexpected.trace" ]] || fail 'tools lifecycle executed the prune command'
pass

# The prune command validates invocation and Omarchy version before mutation.
prune="$REPO_DIR/packages/omarchy/tools/.local/bin/dotfiles-omarchy-prune"
prune_home="$(new_home prune)"
if TEST_OUTPUT="$(HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" unexpected 2>&1)"; then
  fail 'prune command accepted arguments'
else
  assert_contains "$TEST_OUTPUT" 'usage: dotfiles-omarchy-prune'
fi
[[ ! -e "$prune_home/prune-unexpected.trace" ]] || fail 'argument rejection invoked Omarchy'

missing_bin="$TEST_ROOT/missing-omarchy-bin"
mkdir "$missing_bin"
if TEST_OUTPUT="$(HOME="$prune_home" PATH="$missing_bin" /usr/bin/bash "$prune" 2>&1)"; then
  fail 'prune command accepted a host without Omarchy'
else
  assert_contains "$TEST_OUTPUT" 'requires native Omarchy v4'
fi

cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$*" == version ]] && { printf '5.0.0-1\n'; exit 0; }
printf '%s\n' "$*" >> "$HOME/prune-unexpected.trace"
exit 99
SCRIPT
chmod 0755 "$fake_bin/omarchy"
if TEST_OUTPUT="$(HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" 2>&1)"; then
  fail 'prune command accepted unsupported Omarchy'
else
  assert_contains "$TEST_OUTPUT" 'requires native Omarchy v4, found 5.0.0-1'
fi
[[ ! -e "$prune_home/prune-unexpected.trace" ]] || fail 'version rejection mutated Omarchy'
pass

# The AMDGPU IPS helper is hardware-gated, reports boot/configuration state,
# and mutates only its dedicated fixture path through recorded boundaries.
ips="$REPO_DIR/packages/omarchy/tools/.local/bin/dotfiles-omarchy-amdgpu-ips"
ips_home="$(new_home ips)"
ips_root="$(make_system_fixture ips)"
mkdir -p "$ips_root/etc/limine-entry-tool.d" "$ips_root/etc/default" \
  "$ips_root/etc/kernel" "$ips_root/sys/class/dmi/id" "$ips_root/proc"
printf 'Framework\n' > "$ips_root/sys/class/dmi/id/sys_vendor"
printf 'Laptop 13 (AMD Ryzen AI 300 Series)\n' > "$ips_root/sys/class/dmi/id/product_name"
printf 'FRANMGCP09\n' > "$ips_root/sys/class/dmi/id/board_name"
printf 'quiet rw\n' > "$ips_root/proc/cmdline"
: > "$ips_root/etc/kernel/cmdline"
: > "$ips_root/etc/limine-entry-tool.conf"
: > "$ips_home/admin.trace"
: > "$ips_home/limine.trace"

cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$*" == version ]] && { printf '4.0.1-1\n'; exit 0; }
exit 99
SCRIPT
cat > "$fake_bin/lspci" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$*" == -Dn ]] || exit 99
printf 'c1:00.0 0300: 1002:150e (rev c5)\n'
SCRIPT
cat > "$fake_bin/sudo" <<'SCRIPT'
#!/usr/bin/env bash
printf 'sudo' >> "$HOME/admin.trace"
printf '|%s' "$@" >> "$HOME/admin.trace"
printf '\n' >> "$HOME/admin.trace"
case "$1" in
  install)
    source_path="${@: -2:1}"
    target_path="${@: -1}"
    mkdir -p "${target_path%/*}"
    cp -- "$source_path" "$target_path"
    chmod 0644 "$target_path"
    ;;
  rm) rm -- "${@: -1}" ;;
  *) exit 98 ;;
esac
SCRIPT
cat > "$fake_bin/limine-mkinitcpio" <<'SCRIPT'
#!/usr/bin/env bash
printf 'rebuild\n' >> "$HOME/limine.trace"
if [[ -s "$HOME/limine-failures" ]]; then
  failures="$(< "$HOME/limine-failures")"
  if ((failures > 0)); then
    printf '%s\n' "$((failures - 1))" > "$HOME/limine-failures"
    exit 1
  fi
fi
SCRIPT
chmod 0755 "$fake_bin/omarchy" "$fake_bin/lspci" "$fake_bin/sudo" "$fake_bin/limine-mkinitcpio"

run_ips() {
  if TEST_OUTPUT="$(HOME="$ips_home" PATH="$fake_bin:$PATH" DOTFILES_TESTING=1 \
    DOTFILES_TEST_SYSTEM_ROOT="$ips_root" "$ips" "$@" 2>&1)"; then
    TEST_RC=0
  else
    TEST_RC=$?
  fi
}

run_ips
((TEST_RC == 2)) || fail 'AMDGPU IPS helper accepted a missing command'
assert_contains "$TEST_OUTPUT" 'usage: dotfiles-omarchy-amdgpu-ips status|apply|remove'
run_ips unexpected
((TEST_RC == 2)) || fail 'AMDGPU IPS helper accepted an unknown command'
[[ ! -s "$ips_home/admin.trace" && ! -s "$ips_home/limine.trace" ]] ||
  fail 'AMDGPU IPS invocation rejection performed mutation'

run_ips status
((TEST_RC == 1)) || fail 'AMDGPU IPS absent status did not request action'
assert_contains "$TEST_OUTPUT" 'hardware: supported'
assert_contains "$TEST_OUTPUT" 'configuration: absent'
assert_contains "$TEST_OUTPUT" 'running-kernel: disabled'
assert_contains "$TEST_OUTPUT" 'action: apply'

printf 'Other Vendor\n' > "$ips_root/sys/class/dmi/id/sys_vendor"
run_ips status
((TEST_RC == 2)) || fail 'AMDGPU IPS helper accepted mismatched hardware'
assert_contains "$TEST_OUTPUT" 'unsupported DMI system vendor'
printf 'Framework\n' > "$ips_root/sys/class/dmi/id/sys_vendor"
[[ ! -s "$ips_home/admin.trace" && ! -s "$ips_home/limine.trace" ]] ||
  fail 'AMDGPU IPS status performed mutation'
pass

managed="$ips_root/etc/limine-entry-tool.d/90-dotfiles-amdgpu-ips.conf"
run_ips apply
((TEST_RC == 0)) || fail 'AMDGPU IPS apply failed'
[[ "$(< "$managed")" == 'KERNEL_CMDLINE[default]+=" amdgpu.dcdebugmask=0x800"' ]] ||
  fail 'AMDGPU IPS apply wrote unexpected content'
[[ "$(stat -c '%a' "$managed")" == 644 ]] || fail 'AMDGPU IPS apply wrote unexpected mode'
[[ "$(< "$ips_home/limine.trace")" == rebuild ]] || fail 'AMDGPU IPS apply did not rebuild once'
assert_contains "$(< "$ips_home/admin.trace")" 'sudo|install|-D|-o|root|-g|root|-m|0644|--'

run_ips status
((TEST_RC == 1)) || fail 'AMDGPU IPS configured/inactive status did not require reboot'
assert_contains "$TEST_OUTPUT" 'configuration: exact'
assert_contains "$TEST_OUTPUT" 'action: required-reboot'
printf 'quiet amdgpu.dcdebugmask=0x800 rw\n' > "$ips_root/proc/cmdline"
run_ips status
((TEST_RC == 0)) || fail 'AMDGPU IPS active status failed'
assert_contains "$TEST_OUTPUT" 'running-kernel: enabled'
assert_contains "$TEST_OUTPUT" 'action: none'

run_ips apply
((TEST_RC == 0)) || fail 'AMDGPU IPS repeated apply failed'
[[ "$(grep -c '^sudo|install|' "$ips_home/admin.trace")" == 1 ]] ||
  fail 'AMDGPU IPS repeated apply rewrote exact state'
[[ "$(grep -c '^rebuild$' "$ips_home/limine.trace")" == 2 ]] ||
  fail 'AMDGPU IPS repeated apply did not rebuild'
pass

printf 'amdgpu.dcdebugmask=0x400\n' > "$ips_root/etc/kernel/cmdline"
run_ips apply
((TEST_RC == 2)) || fail 'AMDGPU IPS apply accepted a competing assignment'
assert_contains "$TEST_OUTPUT" 'refusing conflicting'
: > "$ips_root/etc/kernel/cmdline"
printf 'KERNEL_CMDLINE[default]="quiet"\n' > "$ips_root/etc/default/limine"
run_ips apply
((TEST_RC == 2)) || fail 'AMDGPU IPS apply accepted a replacing Limine override'
rm "$ips_root/etc/default/limine"

run_ips remove
((TEST_RC == 0)) || fail 'AMDGPU IPS remove failed'
[[ ! -e "$managed" ]] || fail 'AMDGPU IPS remove retained managed state'
assert_contains "$(< "$ips_home/admin.trace")" "sudo|rm|--|$managed"
run_ips remove
((TEST_RC == 0)) || fail 'AMDGPU IPS repeated remove failed'
assert_contains "$TEST_OUTPUT" 'No managed AMDGPU IPS configuration is installed.'
pass

# Failed rebuilds compensate in both directions and retry the rebuild so Limine
# entries converge with the restored configuration.
: > "$ips_home/admin.trace"
: > "$ips_home/limine.trace"
printf '2\n' > "$ips_home/limine-failures"
run_ips apply
((TEST_RC == 1)) || fail 'AMDGPU IPS failed rollback did not fail'
[[ ! -e "$managed" ]] || fail 'AMDGPU IPS failed rollback retained new configuration'
assert_contains "$TEST_OUTPUT" 'boot entries may be mixed, do not reboot'
assert_contains "$TEST_OUTPUT" 'Recovery: sudo rm --'

: > "$ips_home/limine.trace"
printf '1\n' > "$ips_home/limine-failures"
run_ips apply
((TEST_RC == 1)) || fail 'AMDGPU IPS failed apply did not fail'
[[ ! -e "$managed" ]] || fail 'AMDGPU IPS failed apply retained new configuration'
[[ "$(grep -c '^rebuild$' "$ips_home/limine.trace")" == 2 ]] ||
  fail 'AMDGPU IPS failed apply did not rebuild during rollback'

run_ips apply
((TEST_RC == 0)) && [[ -f "$managed" ]] || fail 'AMDGPU IPS setup for remove rollback failed'
: > "$ips_home/limine.trace"
printf '1\n' > "$ips_home/limine-failures"
run_ips remove
((TEST_RC == 1)) || fail 'AMDGPU IPS failed remove did not fail'
[[ -f "$managed" ]] || fail 'AMDGPU IPS failed remove did not restore configuration'
[[ "$(grep -c '^rebuild$' "$ips_home/limine.trace")" == 2 ]] ||
  fail 'AMDGPU IPS failed remove did not rebuild during rollback'
pass

# Successful runs preserve argument boundaries, disable notifications, avoid
# stdin, and converge without touching representative user data.
cat > "$fake_bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" == version ]]; then
  printf '4.0.1-1\n'
  exit 0
fi
printf '%s|%s' "${OMARCHY_REMOVE_NOTIFY:-unset}" "$#" >> "$HOME/prune.trace"
printf '|%s' "$@" >> "$HOME/prune.trace"
printf '\n' >> "$HOME/prune.trace"
SCRIPT
chmod 0755 "$fake_bin/omarchy"
mkdir -p "$prune_home/.config/moonlight" "$prune_home/.config/localsend" \
  "$prune_home/.cache/localsend" "$prune_home/.local/share/applications"
printf 'moonlight-data\n' > "$prune_home/.config/moonlight/config.ini"
printf 'localsend-data\n' > "$prune_home/.config/localsend/settings.json"
printf 'cache-data\n' > "$prune_home/.cache/localsend/session"
printf 'unrelated-launcher\n' > "$prune_home/.local/share/applications/Keep.desktop"
data_hash="$(sha256sum "$prune_home/.config/moonlight/config.ini" \
  "$prune_home/.config/localsend/settings.json" "$prune_home/.cache/localsend/session" \
  "$prune_home/.local/share/applications/Keep.desktop")"
HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" </dev/null >/dev/null
HOME="$prune_home" PATH="$fake_bin:$PATH" "$prune" </dev/null >/dev/null
expected_trace=$'unset|4|pkg|drop|moonlight-qt|localsend\nfalse|3|webapp|remove|HEY\nfalse|3|webapp|remove|Basecamp\nfalse|3|webapp|remove|Zoom\nfalse|3|webapp|remove|Google Messages'
[[ "$(< "$prune_home/prune.trace")" == "$expected_trace"$'\n'"$expected_trace" ]] ||
  fail 'prune command trace is not exact or convergent'
[[ "$(sha256sum "$prune_home/.config/moonlight/config.ini" \
  "$prune_home/.config/localsend/settings.json" "$prune_home/.cache/localsend/session" \
  "$prune_home/.local/share/applications/Keep.desktop")" == "$data_hash" ]] ||
  fail 'prune command changed representative user data'
pass

# Default remove derives package-only tools from the detected profile without
# state and converges again when links are already absent.
expect_success "$home" "$ubuntu" "$DOTFILES" remove
[[ ! -e "$home/.config/mise/conf.d/20-dotfiles-tools.toml" && ! -e "$home/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml" ]] ||
  fail 'default package-only tools removal retained links'
expect_success "$home" "$ubuntu" "$DOTFILES" remove
pass

# Native common fragment has no Node/foundation selectors; Ubuntu alone owns
# the LTS fallback. Managed settings disable implicit installation and locking.
common="$REPO_DIR/packages/common/tools/.config/mise/conf.d/20-dotfiles-tools.toml"
ubuntu_fragment="$REPO_DIR/packages/ubuntu/tools/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml"
! grep -Eq '^(node|git|tmux|neovim|starship|fzf|zoxide|bat|fd|ripgrep)[[:space:]]*=' "$common" || fail 'common tools select a native foundation tool'
! grep -Rqs 'locked = true' "$REPO_DIR/packages/common/tools" "$REPO_DIR/packages/ubuntu/tools" || fail 'tools retained locked mise mode'
grep -qxF 'not_found_auto_install = false' "$common" || fail 'automatic install setting is missing'
grep -qxF 'idiomatic_version_file_enable_tools = []' "$common" || fail 'idiomatic version files are enabled'
grep -qxF 'node = "lts"' "$ubuntu_fragment" || fail 'Ubuntu Node fallback is missing'
pass

# Narrow precedence fixture models accepted mise ordering: a project-local Node
# selector overrides conf.d while the global fallback applies outside projects.
project="$TEST_ROOT/project"
mkdir "$project"
printf '[tools]\nnode = "22.14.0"\n' > "$project/mise.toml"
global_node="$(sed -n 's/^node = "\([^"]*\)"$/\1/p' "$ubuntu_fragment")"
project_node="$(sed -n 's/^node = "\([^"]*\)"$/\1/p' "$project/mise.toml")"
[[ "$global_node" == lts && "$project_node" == 22.14.0 ]] || fail 'project/global selector precedence fixture is invalid'
pass

# Area-specific v1 state refuses conversion without affecting unrelated v1 areas.
home="$(new_home v1)"
mkdir -p "$home/.local/state/dotfiles/v1"
printf '{}\n' > "$home/.local/state/dotfiles/v1/tools.json"
expect_failure "legacy v1 deployment state exists for lean area 'tools'" "$home" "$ubuntu" "$DOTFILES" apply tools
pass

printf 'PASS: %s tools/mise test groups\n' "$TEST_COUNT"
