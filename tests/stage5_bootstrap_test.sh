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
capture() {
  local home="$1"; shift
  set +e
  TEST_OUTPUT="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
    XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" \
    PATH="$home/.local/bin:$fake_bin:/usr/bin:/bin" DOTFILES_TESTING=1 DOTFILES_TEST_ARCH=x86_64 \
    DOTFILES_TEST_HOST_ROOT="$host" FIXTURE_MISE="$mise_artifact" FIXTURE_TOOL="$tool_artifact" \
    GIT_USER_NAME='Stage Five User' GIT_USER_EMAIL='stage5@example.com' "$fixture/bootstrap.sh" "$@" 2>&1)"
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
capture "$home" --check --provision
((TEST_RC == 1)) || fail 'forged receipt backend was accepted'
assert_contains "$TEST_OUTPUT" 'receipt owner identity is invalid for starship'
pass

# A higher-precedence project executable blocks protected resolution and is never probed.
# Restore the accepted receipt generated before the identity corruption.
jq --arg backend 'aqua:starship/starship' '(.tools[] | select(.id == "starship") | .backend)=$backend' "$receipt" > "$receipt.new"
mv "$receipt.new" "$receipt"
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
