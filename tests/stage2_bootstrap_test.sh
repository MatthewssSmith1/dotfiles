#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly BOOTSTRAP="$REPO_DIR/bootstrap.sh"
TEST_ROOT="$(mktemp -d)"
TEST_COUNT=0
TEST_OUTPUT=""
TEST_RC=0

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ -z "$TEST_OUTPUT" ]] || printf '%s\n' "$TEST_OUTPUT" >&2
  exit 1
}

pass() {
  ((TEST_COUNT += 1))
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"
}

assert_file() {
  [[ -f "$1" && ! -L "$1" ]] || fail "expected regular file: $1"
}

assert_empty_home() {
  local entries
  entries="$(find "$1" -mindepth 1 -print -quit)"
  [[ -z "$entries" ]] || fail "expected empty HOME, found $entries"
}

wait_for_file() {
  local path="$1" attempt
  for ((attempt=0; attempt<500; attempt++)); do
    [[ ! -e "$path" ]] || return 0
    sleep 0.01
  done
  fail "timed out waiting for $path"
}

make_host() {
  local name="$1" kind="$2" id="${3:-ubuntu}" version="${4:-24.04}"
  local root="$TEST_ROOT/host-$name"
  mkdir -p "$root/etc" "$root/proc/sys/kernel"
  printf 'ID="%s"\nVERSION_ID="%s"\n' "$id" "$version" > "$root/etc/os-release"
  case "$kind" in
    wsl) printf '6.6.0-MiCrOsOfT-standard-WSL2\n' > "$root/proc/sys/kernel/osrelease" ;;
    linux) printf '6.8.0-generic\n' > "$root/proc/sys/kernel/osrelease" ;;
    *) fail "unknown host fixture kind: $kind" ;;
  esac
  printf '%s' "$root"
}

new_home() {
  local name="$1"
  local home="$TEST_ROOT/home-$name"
  mkdir "$home"
  printf '%s' "$home"
}

capture() {
  local home="$1" host="$2" bootstrap="$3"
  shift 3
  if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" \
    GIT_USER_NAME='Stage Two User' GIT_USER_EMAIL='stage2@example.com' "$bootstrap" "$@" 2>&1)"; then
    TEST_RC=0
  else
    TEST_RC=$?
  fi
}

expect_success() {
  capture "$@"
  ((TEST_RC == 0)) || fail "command unexpectedly failed with $TEST_RC"
}

expect_failure() {
  local expected="$1"
  shift
  capture "$@"
  ((TEST_RC != 0)) || fail 'command unexpectedly succeeded'
  assert_contains "$TEST_OUTPUT" "$expected"
}

prepare_omarchy() {
  local home="$1"
  mkdir -p "$home/.local/share/omarchy/bin" "$home/.config/git"
  printf '3.8.3\n' > "$home/.local/share/omarchy/version"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home/.local/share/omarchy/bin/omarchy-version"
  chmod +x "$home/.local/share/omarchy/bin/omarchy-version"
  cp "$REPO_DIR/packages/upstream/git/.config/git/config" "$home/.config/git/config"
}

readonly BOOTSTRAP_SOURCES=(
  "$BOOTSTRAP"
  "$REPO_DIR/lib/common.sh"
  "$REPO_DIR/lib/host.sh"
  "$REPO_DIR/lib/engine.sh"
  "$REPO_DIR/lib/areas/git.sh"
)
for source_file in "${BOOTSTRAP_SOURCES[@]}"; do
  [[ -f "$source_file" ]] || fail "missing bootstrap source file: $source_file"
done
bash -n "${BOOTSTRAP_SOURCES[@]}" || fail 'a bootstrap source file has invalid Bash syntax'
jq empty "$REPO_DIR/schemas/deployment-state-v1.schema.json" || \
  fail 'Stage 2 JSON is invalid'
grep -Fq 'set -Eeuo pipefail' "$BOOTSTRAP" || fail 'bootstrap strict mode is missing'
if grep -Eq '(^|[[:space:]])stow([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+\.' "${BOOTSTRAP_SOURCES[@]}"; then
  fail 'root Stow is reachable'
fi
pass

generic_host="$(make_host generic linux)"
wsl_host="$(make_host wsl wsl)"
old_wsl_host="$(make_host old-wsl wsl ubuntu 22.04)"
other_host="$(make_host other linux debian 12)"

# Detection, every override, unsupported hosts, conflicts, and partial Omarchy.
home="$(new_home detect-generic)"
expect_success "$home" "$generic_host" "$BOOTSTRAP" --check
assert_contains "$TEST_OUTPUT" "selected profile 'generic'"
expect_success "$home" "$generic_host" "$BOOTSTRAP" --check --profile generic
expect_failure "not allowed" "$home" "$generic_host" "$BOOTSTRAP" --check --profile wsl
expect_failure "not allowed" "$home" "$generic_host" "$BOOTSTRAP" --check --profile omarchy

home="$(new_home detect-wsl)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --check
assert_contains "$TEST_OUTPUT" "selected profile 'wsl'"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --check --profile wsl
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --check --profile generic
assert_contains "$TEST_OUTPUT" 'WSL adapters are omitted'
expect_failure "not allowed" "$home" "$wsl_host" "$BOOTSTRAP" --check --profile omarchy

home="$(new_home detect-omarchy)"
prepare_omarchy "$home"
expect_success "$home" "$generic_host" "$BOOTSTRAP" --check
assert_contains "$TEST_OUTPUT" "selected profile 'omarchy'"
expect_success "$home" "$generic_host" "$BOOTSTRAP" --check --profile omarchy
expect_failure "not allowed" "$home" "$generic_host" "$BOOTSTRAP" --check --profile generic
expect_failure "not allowed" "$home" "$generic_host" "$BOOTSTRAP" --check --profile wsl

home="$(new_home partial-omarchy)"
mkdir -p "$home/.local/share/omarchy"
printf '3.8.3\n' > "$home/.local/share/omarchy/version"
expect_failure 'partial Omarchy installation' "$home" "$generic_host" "$BOOTSTRAP" --check
home="$(new_home conflicting-host)"
prepare_omarchy "$home"
expect_failure 'conflicting host signals' "$home" "$wsl_host" "$BOOTSTRAP" --check
home="$(new_home unsupported-old-wsl)"
expect_failure 'not supported for mutation' "$home" "$old_wsl_host" "$BOOTSTRAP" --check
expect_failure 'not allowed' "$home" "$old_wsl_host" "$BOOTSTRAP" --check --profile wsl
home="$(new_home unsupported-other)"
expect_failure 'not supported for mutation' "$home" "$other_host" "$BOOTSTRAP" --check
if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$generic_host" \
  DOTFILES_TEST_UNAME=Darwin GIT_USER_NAME=User GIT_USER_EMAIL=user@example.com "$BOOTSTRAP" --check 2>&1)"; then
  fail 'non-Linux host was accepted'
fi
assert_contains "$TEST_OUTPUT" 'unsupported host'
pass

# Stage 2 CLI and deduplication.
home="$(new_home cli)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --check --area git --area git
expect_failure "area 'bash' is not implemented" "$home" "$wsl_host" "$BOOTSTRAP" --check --area bash
expect_failure 'invalid profile' "$home" "$wsl_host" "$BOOTSTRAP" --check --profile Generic
expect_failure '--profile is invalid with --remove' "$home" "$wsl_host" "$BOOTSTRAP" --remove --profile wsl
expect_failure 'usage:' "$home" "$wsl_host" "$BOOTSTRAP" --unknown
pass

# Check is non-mutating and repeated shared locks coexist.
home="$(new_home check-clean)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --check
assert_empty_home "$home"
(
  exec {fd}<"$home"
  flock --shared "$fd"
  sleep 2
) &
lock_pid=$!
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --check
wait "$lock_pid"
assert_empty_home "$home"
pass

# Exact deterministic missing-package output and no package-manager execution.
home="$(new_home missing-dependency)"
fake_bin="$TEST_ROOT/missing-bin"
mkdir "$fake_bin"
for command in dirname git jq flock realpath uname; do ln -s "$(command -v "$command")" "$fake_bin/$command"; done
cat > "$fake_bin/sudo" <<EOF
#!/usr/bin/env bash
/usr/bin/touch '$TEST_ROOT/sudo-ran'
exit 99
EOF
chmod +x "$fake_bin/sudo"
if TEST_OUTPUT="$(PATH="$fake_bin" HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  /usr/bin/bash "$BOOTSTRAP" --check 2>&1)"; then
  fail 'missing Stow dependency was accepted'
fi
assert_contains "$TEST_OUTPUT" 'sudo apt-get install -y stow'
[[ ! -e "$TEST_ROOT/sudo-ran" ]] || fail 'bootstrap executed sudo'
assert_empty_home "$home"
pass

# The dependency manifest remains usable when jq and Stow are both absent.
home="$(new_home missing-bootstrap-dependencies)"
fake_bin="$TEST_ROOT/missing-bootstrap-bin"
mkdir "$fake_bin"
for command in dirname git flock realpath uname; do ln -s "$(command -v "$command")" "$fake_bin/$command"; done
if TEST_OUTPUT="$(PATH="$fake_bin" HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  /usr/bin/bash "$BOOTSTRAP" --check 2>&1)"; then
  fail 'missing jq and Stow dependencies were accepted'
fi
assert_contains "$TEST_OUTPUT" 'sudo apt-get install -y jq stow'
assert_empty_home "$home"
pass

# Managed writes refuse symlinked parent directories and never touch their targets.
external="$TEST_ROOT/external-parent"
mkdir "$external"
home="$(new_home symlinked-config-parent)"
ln -s "$external" "$home/.config"
expect_failure 'symlinked, non-directory, or escaping parent' "$home" "$wsl_host" "$BOOTSTRAP"
[[ -z "$(find "$external" -mindepth 1 -print -quit)" ]] || fail 'symlinked config parent target was modified'
home="$(new_home symlinked-state-parent)"
mkdir "$home/.local"
ln -s "$external" "$home/.local/state"
expect_failure 'symlinked' "$home" "$wsl_host" "$BOOTSTRAP"
[[ -z "$(find "$external" -mindepth 1 -print -quit)" ]] || fail 'symlinked state parent target was modified'
pass

# Generic uses the same ordered three-layer closure without WSL selection.
home="$(new_home generic-lifecycle)"
expect_success "$home" "$generic_host" "$BOOTSTRAP"
[[ "$(jq -c .packages "$home/.local/state/dotfiles/v1/git.json")" == '["upstream/git","generic/git","common/git"]' ]] || \
  fail 'Generic closure order is wrong'
[[ "$(jq -r .profile "$home/.local/state/dotfiles/v1/git.json")" == generic ]] || fail 'Generic state profile is wrong'
expect_success "$home" "$generic_host" "$BOOTSTRAP" --remove
pass

# Real Stow apply, closure order, origins, repository precedence, idempotence, and removal.
home="$(new_home lifecycle)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --area git --area git
state="$home/.local/state/dotfiles/v1/git.json"
assert_file "$state"
[[ "$(jq -c .packages "$state")" == '["upstream/git","generic/git","common/git"]' ]] || fail 'WSL closure order is wrong'
[[ -L "$home/.config/git/config" && -L "$home/.config/dotfiles/personal/git.conf" ]] || fail 'Stow links are missing'
assert_file "$home/.gitconfig"
assert_file "$home/.gitconfig.local"
[[ "$(stat -c %a "$home/.gitconfig.local")" == 600 ]] || fail 'identity mode is not 0600'
[[ "$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --get init.defaultBranch)" == main ]] || \
  fail 'personal default branch does not win'
origin="$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --show-origin --get init.defaultBranch)"
assert_contains "$origin" '.config/dotfiles/personal/git.conf'
baseline_origin="$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$home" config --includes --show-origin --get alias.co)"
assert_contains "$baseline_origin" '.config/git/config'
origin="$(HOME="$home" git -C "$home" config --includes --show-origin --show-scope --get init.defaultBranch)"
[[ "$origin" == global$'\t'file:"$home/.config/dotfiles/personal/git.conf"$'\t'main ]] || \
  fail 'personal value scope or origin is wrong'
for key in alias.co alias.br alias.ci alias.st pull.rebase push.autoSetupRemote diff.algorithm diff.colorMoved \
  diff.mnemonicPrefix commit.verbose column.ui branch.sort tag.sort rerere.enabled rerere.autoupdate; do
  origin="$(HOME="$home" git -C "$home" config --includes --show-origin --show-scope --get "$key")"
  [[ "$origin" == global$'\t'file:"$home/.config/git/config"$'\t'* ]] || \
    fail "$key scope or baseline origin is wrong"
done
for key in user.name user.email; do
  origin="$(HOME="$home" git -C "$home" config --includes --show-origin --show-scope --get "$key")"
  [[ "$origin" == global$'\t'file:"$home/.gitconfig.local"$'\t'* ]] || \
    fail "$key scope or identity origin is wrong"
done
repo="$TEST_ROOT/repository"
mkdir "$repo"
git -C "$repo" init -q
git -C "$repo" config init.defaultBranch repository-branch
[[ "$(HOME="$home" GIT_CONFIG_NOSYSTEM=1 git -C "$repo" config --get init.defaultBranch)" == repository-branch ]] || \
  fail 'repository config did not retain precedence'
identity_hash="$(sha256sum "$home/.gitconfig.local")"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
[[ "$(sha256sum "$home/.gitconfig.local")" == "$identity_hash" ]] || fail 'rerun changed established identity'
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --remove
[[ ! -e "$state" && ! -L "$home/.config/git/config" && ! -L "$home/.config/dotfiles/personal/git.conf" ]] || \
  fail 'removal left managed state or links'
assert_file "$home/.gitconfig.local"
assert_file "$home/.config/dotfiles/local/git.conf"
[[ ! -e "$home/.gitconfig" && ! -L "$home/.gitconfig" ]] || fail 'remove retained an empty managed global file'
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
assert_file "$home/.gitconfig"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --remove
pass

# Removal is state-driven and ignores later partial host signals.
home="$(new_home state-driven-remove)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
mkdir -p "$home/.local/share/omarchy"
printf 'partial\n' > "$home/.local/share/omarchy/version"
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --remove
[[ ! -e "$home/.local/state/dotfiles/v1/git.json" ]] || fail 'state-driven removal left Git state'
pass

# Omarchy closure keeps the native baseline untouched.
home="$(new_home omarchy-apply)"
prepare_omarchy "$home"
native_hash="$(sha256sum "$home/.config/git/config")"
expect_success "$home" "$generic_host" "$BOOTSTRAP"
[[ "$(jq -c .packages "$home/.local/state/dotfiles/v1/git.json")" == '["common/git"]' ]] || fail 'Omarchy closure is wrong'
[[ "$(sha256sum "$home/.config/git/config")" == "$native_hash" && ! -L "$home/.config/git/config" ]] || \
  fail 'Omarchy native Git baseline was changed'
expect_success "$home" "$generic_host" "$BOOTSTRAP" --remove
[[ "$(sha256sum "$home/.config/git/config")" == "$native_hash" ]] || fail 'Omarchy removal changed native config'
pass

# Package traversal, missing roots, and duplicate targets are rejected before Stow.
fixture="$TEST_ROOT/package-fixture"
mkdir "$fixture"
cp -a "$REPO_DIR/." "$fixture/"
home="$(new_home package-errors)"
printf '# area closure\ngit ../git\n' > "$fixture/profiles/wsl.conf"
expect_failure 'invalid qualified package ID' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check
printf '# area closure\ngit missing/git\n' > "$fixture/profiles/wsl.conf"
expect_failure 'missing package root' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check
printf '# area closure\ngit upstream/git,generic/git,common/git\n' > "$fixture/profiles/wsl.conf"
mkdir -p "$fixture/packages/generic/git/.config/dotfiles/personal"
printf '[init]\n\tdefaultBranch = duplicate\n' > "$fixture/packages/generic/git/.config/dotfiles/personal/git.conf"
expect_failure 'duplicate payload target' "$home" "$wsl_host" "$fixture/bootstrap.sh" --check
assert_empty_home "$home"
pass

# Legacy absolute links migrate safely, preserving credential resets and dropping autostash.
fixture="$TEST_ROOT/legacy-fixture"
mkdir "$fixture"
cp -a "$REPO_DIR/." "$fixture/"
printf '[user]\n\tname = Legacy User\n\temail = legacy@example.com\n' > "$fixture/.gitconfig.local"
helper="$TEST_ROOT/fake-credential-helper"
cat > "$helper" <<'EOF'
#!/usr/bin/env bash
while IFS= read -r line && [[ -n "$line" ]]; do :; done
printf 'username=fake-user\npassword=fake-password\n'
EOF
chmod +x "$helper"
cat >> "$fixture/.gitconfig" <<EOF
[credential]
	helper =
	helper = !$helper
EOF
home="$(new_home legacy)"
ln -s "$fixture/.gitconfig" "$home/.gitconfig"
ln -s "$fixture/.gitconfig.local" "$home/.gitconfig.local"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh"
assert_file "$home/.gitconfig"
assert_file "$home/.gitconfig.local"
[[ "$(stat -c %a "$home/.gitconfig.local")" == 600 ]] || fail 'legacy identity was not safely protected'
[[ "$(git config --file "$home/.gitconfig.local" --get user.name)" == 'Legacy User' ]] || fail 'legacy identity changed'
mapfile -t helpers < <(git config --file "$home/.config/dotfiles/local/git.conf" --get-all credential.https://github.com.helper)
[[ ${#helpers[@]} == 2 && -z "${helpers[0]}" && "${helpers[1]}" == '!/usr/bin/gh auth git-credential' ]] || \
  fail 'ordered credential reset/helper entries were not preserved'
if git config --file "$home/.config/dotfiles/local/git.conf" --get rebase.autostash >/dev/null 2>&1; then
  fail 'rebase.autostash was retained'
fi
credential="$(printf 'protocol=https\nhost=auth.example\n\n' | HOME="$home" GIT_CONFIG_NOSYSTEM=1 \
  GIT_TERMINAL_PROMPT=0 git credential fill)"
assert_contains "$credential" 'username=fake-user'
assert_contains "$credential" 'password=fake-password'
http_root="$TEST_ROOT/http-root"
http_source="$TEST_ROOT/http-source"
mkdir "$http_root"
git init -q -b main "$http_source"
printf 'authenticated\n' > "$http_source/proof.txt"
git -C "$http_source" add proof.txt
git -C "$http_source" -c user.name=Fixture -c user.email=fixture@example.com commit -qm fixture
git clone -q --bare "$http_source" "$http_root/repo.git"
git -C "$http_root/repo.git" update-server-info
server_script="$TEST_ROOT/auth-server.py"
cat > "$server_script" <<'PY'
import base64
import http.server
import pathlib
import sys

root = sys.argv[1]
port_file = pathlib.Path(sys.argv[2])
expected = "Basic " + base64.b64encode(b"fake-user:fake-password").decode("ascii")

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def do_GET(self):
        if self.headers.get("Authorization") != expected:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="stage2"')
            self.end_headers()
            return
        super().do_GET()

    def log_message(self, format, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(server.server_port), encoding="ascii")
server.serve_forever()
PY
port_file="$TEST_ROOT/auth-server.port"
python3 "$server_script" "$http_root" "$port_file" > "$TEST_ROOT/auth-server.log" 2>&1 &
server_pid=$!
wait_for_file "$port_file"
fetch_repo="$TEST_ROOT/auth-fetch"
git init -q "$fetch_repo"
HOME="$home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  git -C "$fetch_repo" fetch -q "http://127.0.0.1:$(<"$port_file")/repo.git" refs/heads/main || \
  fail 'authenticated fetch through migrated fake helper failed'
kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
ledger="$home/.local/state/dotfiles/v1/migrations.json"
assert_file "$ledger"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
assert_file "$ledger"
assert_file "$home/.gitconfig.local"
assert_file "$home/.config/dotfiles/local/git.conf"
pass

# Known relative legacy links are accepted with the same exact ownership checks.
fixture="$TEST_ROOT/relative-legacy-fixture"
mkdir "$fixture"
cp -a "$REPO_DIR/." "$fixture/"
printf '[user]\n\tname = Relative User\n\temail = relative@example.com\n' > "$fixture/.gitconfig.local"
home="$fixture/test-home"
mkdir "$home"
ln -s ../.gitconfig "$home/.gitconfig"
ln -s ../.gitconfig.local "$home/.gitconfig.local"
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh"
assert_file "$home/.gitconfig"
assert_file "$home/.gitconfig.local"
pass

# Unknown identity links, regular identity protection, and fresh env creation.
home="$(new_home identity-link-conflict)"
identity_target="$TEST_ROOT/unowned-identity"
printf '[user]\n\tname = Do Not Touch\n\temail = untouched@example.com\n' > "$identity_target"
chmod 0644 "$identity_target"
ln -s "$identity_target" "$home/.gitconfig.local"
expect_failure 'unknown identity symlink' "$home" "$wsl_host" "$BOOTSTRAP"
[[ "$(stat -c %a "$identity_target")" == 644 ]] || fail 'unknown identity symlink was followed by chmod'
home="$(new_home identity-mode)"
printf '[user]\n\tname = Established\n\temail = established@example.com\n' > "$home/.gitconfig.local"
chmod 0644 "$home/.gitconfig.local"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
[[ "$(stat -c %a "$home/.gitconfig.local")" == 600 ]] || fail 'regular identity was not safely replaced at mode 0600'
[[ "$(git config --file "$home/.gitconfig.local" --get user.name)" == Established ]] || fail 'env overwrote established identity'
home="$(new_home identity-missing)"
if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" "$BOOTSTRAP" 2>&1)"; then
  fail 'missing identity without environment was accepted'
fi
assert_contains "$TEST_OUTPUT" 'set both GIT_USER_NAME and GIT_USER_EMAIL'
home="$(new_home identity-placeholder)"
cp "$REPO_DIR/.gitconfig.local.example" "$home/.gitconfig.local"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
[[ "$(git config --file "$home/.gitconfig.local" --get-all user.name | wc -l)" == 1 ]] || fail 'placeholder name was duplicated'
[[ "$(git config --file "$home/.gitconfig.local" --get user.name)" == 'Stage Two User' ]] || fail 'placeholder name was not replaced'
pass

# Guarded regular-file preservation, malformed markers, and exact block removal.
home="$(new_home guarded)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
global_tmp="$home/.gitconfig.rewrite"
{
  printf '# unrelated before\n'
  cat "$home/.gitconfig"
  printf '# unrelated after\n'
} > "$global_tmp"
mv "$global_tmp" "$home/.gitconfig"
chmod 0640 "$home/.gitconfig"
global_hash="$(sha256sum "$home/.gitconfig")"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
[[ "$(sha256sum "$home/.gitconfig")" == "$global_hash" ]] || fail 'valid guarded file bytes changed on apply'
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --remove
[[ "$(cat "$home/.gitconfig")" == $'# unrelated before\n# unrelated after' ]] || fail 'remove changed unrelated global bytes'
[[ "$(stat -c %a "$home/.gitconfig")" == 640 ]] || fail 'guarded replacement did not preserve mode'
home="$(new_home guarded-unknown)"
printf '[core]\n\teditor = false\n' > "$home/.gitconfig"
expect_failure 'missing, malformed, nested, duplicate, or modified managed block' "$home" "$wsl_host" "$BOOTSTRAP"
home="$(new_home guarded-malformed)"
printf '# >>> dotfiles managed git includes >>>\n# >>> dotfiles managed git includes >>>\n' > "$home/.gitconfig"
expect_failure 'missing, malformed, nested, duplicate, or modified managed block' "$home" "$wsl_host" "$BOOTSTRAP"
home="$(new_home guarded-invalid-syntax)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
printf '\n[broken\n' >> "$home/.gitconfig"
expect_failure 'not valid Git configuration' "$home" "$wsl_host" "$BOOTSTRAP" --check
home="$(new_home guarded-link)"
printf '[core]\n\teditor = false\n' > "$TEST_ROOT/unowned-global"
ln -s "$TEST_ROOT/unowned-global" "$home/.gitconfig"
expect_failure 'unknown global-config symlink' "$home" "$wsl_host" "$BOOTSTRAP"
pass

# Existing central local files are not modified and must contain migration values.
fixture="$TEST_ROOT/local-fixture"
mkdir "$fixture"
cp -a "$REPO_DIR/." "$fixture/"
printf '[user]\n\tname = Legacy\n\temail = legacy@example.com\n' > "$fixture/.gitconfig.local"
home="$(new_home local-conflict)"
mkdir -p "$home/.config/dotfiles/local"
printf '[core]\n\teditor = host-editor\n' > "$home/.config/dotfiles/local/git.conf"
local_hash="$(sha256sum "$home/.config/dotfiles/local/git.conf")"
ln -s "$fixture/.gitconfig" "$home/.gitconfig"
ln -s "$fixture/.gitconfig.local" "$home/.gitconfig.local"
expect_failure 'does not preserve required values' "$home" "$wsl_host" "$fixture/bootstrap.sh"
[[ "$(sha256sum "$home/.config/dotfiles/local/git.conf")" == "$local_hash" ]] || fail 'existing central local file was modified'
pass

# Lock contention is nonblocking and exclusive for mutation.
home="$(new_home lock)"
(
  exec {fd}<"$home"
  flock --exclusive "$fd"
  sleep 2
) &
lock_pid=$!
sleep 0.2
expect_failure 'HOME lock' "$home" "$wsl_host" "$BOOTSTRAP"
wait "$lock_pid"
assert_empty_home "$home"
pass

# Two real bootstrap processes contend on the HOME lock.
home="$(new_home process-lock)"
hold_dir="$TEST_ROOT/process-lock-hold"
mkdir "$hold_dir"
HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  DOTFILES_TEST_HOLD_AT=after-lock DOTFILES_TEST_HOLD_DIR="$hold_dir" \
  GIT_USER_NAME=Lock GIT_USER_EMAIL=lock@example.com "$BOOTSTRAP" > "$TEST_ROOT/process-lock.log" 2>&1 &
lock_pid=$!
wait_for_file "$hold_dir/after-lock.ready"
expect_failure 'another deployment holds the HOME lock' "$home" "$wsl_host" "$BOOTSTRAP"
: > "$hold_dir/after-lock.release"
wait "$lock_pid" || fail 'lock-holding bootstrap failed after release'
expect_success "$home" "$wsl_host" "$BOOTSTRAP" --remove
pass

# Guarded global replacement remains old or new, never partially written.
fixture="$TEST_ROOT/atomic-fixture"
mkdir "$fixture"
cp -a "$REPO_DIR/." "$fixture/"
printf '[user]\n\tname = Atomic User\n\temail = atomic@example.com\n' > "$fixture/.gitconfig.local"
home="$(new_home atomic-replacement)"
ln -s "$fixture/.gitconfig" "$home/.gitconfig"
ln -s "$fixture/.gitconfig.local" "$home/.gitconfig.local"
hold_dir="$TEST_ROOT/atomic-hold"
mkdir "$hold_dir"
HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  DOTFILES_TEST_HOLD_AT=before-atomic-rename DOTFILES_TEST_HOLD_DIR="$hold_dir" \
  GIT_USER_NAME=Atomic GIT_USER_EMAIL=atomic@example.com "$fixture/bootstrap.sh" > "$TEST_ROOT/atomic.log" 2>&1 &
atomic_pid=$!
wait_for_file "$hold_dir/before-atomic-rename.ready"
[[ -L "$home/.gitconfig" && "$(readlink -- "$home/.gitconfig")" == "$fixture/.gitconfig" ]] || \
  fail 'global config changed before its atomic rename'
: > "$hold_dir/before-atomic-rename.release"
wait "$atomic_pid" || fail 'atomic replacement bootstrap failed after release'
assert_file "$home/.gitconfig"
grep -Fq '# >>> dotfiles managed git includes >>>' "$home/.gitconfig" || fail 'atomic replacement content is incomplete'
expect_success "$home" "$wsl_host" "$fixture/bootstrap.sh" --remove
pass

# Malformed/newer state, profile mismatch, and ownership drift refuse mutation.
home="$(new_home states)"
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
state="$home/.local/state/dotfiles/v1/git.json"
cp "$state" "$TEST_ROOT/state-good.json"
printf '{bad json\n' > "$state"
expect_failure 'malformed or unknown deployment state' "$home" "$wsl_host" "$BOOTSTRAP"
cp "$TEST_ROOT/state-good.json" "$state"
jq '.schema_version = 2' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
expect_failure 'newer deployment state schema 2' "$home" "$wsl_host" "$BOOTSTRAP"
cp "$TEST_ROOT/state-good.json" "$state"
jq '.profile = "generic"' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
expect_failure 'run --remove before changing profiles' "$home" "$wsl_host" "$BOOTSTRAP"
cp "$TEST_ROOT/state-good.json" "$state"
ln -sfn /tmp/unowned "$home/.config/git/config"
expect_failure 'different lexical ownership' "$home" "$wsl_host" "$BOOTSTRAP" --remove
[[ -f "$state" ]] || fail 'drifted removal deleted state'
pass

# A moved checkout is reconciled from recorded lexical and resolved ownership.
move_root="$TEST_ROOT/move"
mkdir "$move_root"
cp -a "$REPO_DIR/." "$move_root/repo-one"
home="$(new_home moved-checkout)"
expect_success "$home" "$wsl_host" "$move_root/repo-one/bootstrap.sh"
cp -a "$move_root/repo-one" "$move_root/repo-two"
rm -rf "$move_root/repo-one"
readonly_tmp="$TEST_ROOT/moved-check-readonly-tmp"
mkdir "$readonly_tmp"
chmod 0555 "$readonly_tmp"
state_hash="$(sha256sum "$home/.local/state/dotfiles/v1/git.json")"
old_link="$(readlink -- "$home/.config/git/config")"
if ! TEST_OUTPUT="$(TMPDIR="$readonly_tmp" HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  GIT_USER_NAME='Stage Two User' GIT_USER_EMAIL=stage2@example.com "$move_root/repo-two/bootstrap.sh" --check 2>&1)"; then
  fail 'moved-checkout check failed without a writable temporary directory'
fi
[[ -z "$(find "$readonly_tmp" -mindepth 1 -print -quit)" ]] || fail 'moved-checkout check mutated TMPDIR'
[[ "$(sha256sum "$home/.local/state/dotfiles/v1/git.json")" == "$state_hash" && \
  "$(readlink -- "$home/.config/git/config")" == "$old_link" ]] || fail 'moved-checkout check mutated HOME'
expect_success "$home" "$wsl_host" "$move_root/repo-two/bootstrap.sh"
[[ "$(jq -r .checkout_root "$home/.local/state/dotfiles/v1/git.json")" == "$move_root/repo-two" ]] || \
  fail 'state did not move to the new checkout'
[[ "$(realpath "$home/.config/git/config")" == "$move_root/repo-two/packages/upstream/git/.config/git/config" ]] || \
  fail 'Stow link did not move to the new checkout'
pass

# Pre-state moved and broken legacy links use only exact reviewed inventory ownership.
for topology in moved broken; do
  legacy_root="$TEST_ROOT/legacy-$topology-old"
  current_root="$TEST_ROOT/legacy-$topology-current"
  cp -a "$REPO_DIR" "$legacy_root"
  cp -a "$REPO_DIR" "$current_root"
  home="$(new_home "legacy-$topology-checkout")"
  printf '[user]\n\tname = Inventory User\n\temail = inventory@example.com\n' > "$home/.gitconfig.local"
  ln -s "$legacy_root/.gitconfig" "$home/.gitconfig"
  jq --arg home "$home" --arg root "$legacy_root" \
    '.hosts[0].home = $home | .hosts[0].checkout_root = $root' \
    "$current_root/manifests/legacy-links.json" > "$current_root/manifests/legacy-links.json.tmp"
  mv "$current_root/manifests/legacy-links.json.tmp" "$current_root/manifests/legacy-links.json"
  if [[ "$topology" == broken ]]; then rm -rf -- "$legacy_root"; fi
  expect_success "$home" "$wsl_host" "$current_root/bootstrap.sh"
  assert_file "$home/.gitconfig"
  [[ -L "$home/.config/git/config" ]] || fail "$topology legacy checkout did not deploy Git"
done
pass

# Every exposed mutation fault rolls back and leaves state uncommitted.
for point in after-local after-identity after-stow after-global before-state; do
  home="$(new_home "fault-$point")"
  if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
    DOTFILES_TEST_FAIL_AT="$point" GIT_USER_NAME=Fault GIT_USER_EMAIL=fault@example.com "$BOOTSTRAP" 2>&1)"; then
    fail "fault injection unexpectedly succeeded at $point"
  fi
  assert_contains "$TEST_OUTPUT" "injected test failure at $point"
  assert_contains "$TEST_OUTPUT" 'rolled back incomplete Git deployment'
  assert_empty_home "$home"
done
home="$(new_home fault-after-state-commit)"
if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
  DOTFILES_TEST_FAIL_AT=after-state-commit GIT_USER_NAME=Fault GIT_USER_EMAIL=fault@example.com "$BOOTSTRAP" 2>&1)"; then
  fail 'post-state fault injection unexpectedly succeeded'
fi
assert_contains "$TEST_OUTPUT" 'injected test failure at after-state-commit'
assert_file "$home/.local/state/dotfiles/v1/git.json"
[[ -L "$home/.config/git/config" ]] || fail 'committed state fault lost deployed links'
expect_success "$home" "$wsl_host" "$BOOTSTRAP"
for point in remove-after-links remove-after-global; do
  home="$(new_home "fault-$point")"
  expect_success "$home" "$wsl_host" "$BOOTSTRAP"
  state_hash="$(sha256sum "$home/.local/state/dotfiles/v1/git.json")"
  global_hash="$(sha256sum "$home/.gitconfig")"
  if TEST_OUTPUT="$(HOME="$home" DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$wsl_host" \
    DOTFILES_TEST_FAIL_AT="$point" "$BOOTSTRAP" --remove 2>&1)"; then
    fail "removal fault injection unexpectedly succeeded at $point"
  fi
  assert_contains "$TEST_OUTPUT" 'rolled back incomplete Git deployment'
  [[ "$(sha256sum "$home/.local/state/dotfiles/v1/git.json")" == "$state_hash" ]] || fail 'removal rollback changed state'
  [[ "$(sha256sum "$home/.gitconfig")" == "$global_hash" ]] || fail 'removal rollback changed global config'
  [[ -L "$home/.config/git/config" && -L "$home/.config/dotfiles/personal/git.conf" ]] || fail 'removal rollback lost links'
done
home="$(new_home guarded-fault-env)"
if TEST_OUTPUT="$(HOME="$home" DOTFILES_TEST_FAIL_AT=after-local GIT_USER_NAME=Fault GIT_USER_EMAIL=fault@example.com \
  "$BOOTSTRAP" 2>&1)"; then
  fail 'unguarded fault injection was accepted'
fi
assert_contains "$TEST_OUTPUT" 'requires DOTFILES_TESTING=1'
pass

printf 'PASS: %s Stage 2 Git deployment test groups\n' "$TEST_COUNT"
