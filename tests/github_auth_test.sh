#!/usr/bin/env bash

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

readonly WRAPPER_SOURCE="$REPO_DIR/packages/ubuntu/git/.local/bin/gh"
readonly HELPER="$REPO_DIR/packages/ubuntu/git/.local/share/dotfiles/bin/dotfiles-github-auth"
readonly FIXTURE_TOKEN='fixture-vps-token-value'
backend_root="$TEST_ROOT/backend-root"
mkdir -p "$backend_root/usr/bin"
cat > "$backend_root/usr/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$CAPTURE_DIR/args"
env > "$CAPTURE_DIR/environment"
if [[ ! -t 0 ]]; then cat > "$CAPTURE_DIR/stdin"; fi
printf 'native-output\n'
printf 'native-error\n' >&2
exit "${BACKEND_STATUS:-0}"
SCRIPT
chmod 0755 "$backend_root/usr/bin/gh"
WRAPPER="$TEST_ROOT/gh"
sed "s|^BACKEND=/usr/bin/gh$|BACKEND=$backend_root/usr/bin/gh|" "$WRAPPER_SOURCE" > "$WRAPPER"
chmod 0755 "$WRAPPER"
readonly WRAPPER

new_auth_home() {
  AUTH_HOME="$(new_home "$1")"
  CAPTURE_DIR="$TEST_ROOT/capture-$1"
  mkdir -p "$CAPTURE_DIR" "$AUTH_HOME/.config/dotfiles/git" \
    "$AUTH_HOME/.config/dotfiles/local/secrets" "$AUTH_HOME/.local/share/dotfiles/bin"
  chmod 0700 "$AUTH_HOME" "$AUTH_HOME/.config/dotfiles/local/secrets"
  chmod 0755 "$AUTH_HOME/.config" "$AUTH_HOME/.config/dotfiles" "$AUTH_HOME/.config/dotfiles/local"
  cp "$HELPER" "$AUTH_HOME/.local/share/dotfiles/bin/dotfiles-github-auth"
  chmod 0755 "$AUTH_HOME/.local/share/dotfiles/bin/dotfiles-github-auth"
}

activate() {
  cp "$REPO_DIR/packages/ubuntu/git/.config/dotfiles/git/github-vps.conf" \
    "$AUTH_HOME/.config/dotfiles/git/github-vps.conf"
  printf '[include]\n\tpath = ~/.config/dotfiles/git/github-vps.conf\n' > "$AUTH_HOME/.gitconfig"
}

write_bundles() {
  printf 'GH_TOKEN=%s\n' "$FIXTURE_TOKEN" > "$AUTH_HOME/.config/dotfiles/local/secrets/github-MatthewssSmith1.env"
  printf 'GH_TOKEN=%s\n' "$FIXTURE_TOKEN" > "$AUTH_HOME/.config/dotfiles/local/secrets/github-mimir-db.env"
  chmod 0600 "$AUTH_HOME/.config/dotfiles/local/secrets/"*.env
}

run_gh() {
  local cwd="${RUN_CWD:-$AUTH_HOME}" stdout="$CAPTURE_DIR/stdout" stderr="$CAPTURE_DIR/stderr"
  rm -f "$CAPTURE_DIR/args" "$CAPTURE_DIR/environment" "$CAPTURE_DIR/stdin"
  set +e
  (cd "$cwd" && env HOME="$AUTH_HOME" CAPTURE_DIR="$CAPTURE_DIR" BACKEND_STATUS="${BACKEND_STATUS:-0}" \
    GH_REPO="${INHERITED_REPO:-}" GH_TOKEN="${INHERITED_TOKEN:-}" GITHUB_TOKEN=parent-github-token \
    GH_ENTERPRISE_TOKEN=parent-enterprise-token GITHUB_ENTERPRISE_TOKEN=parent-enterprise-token-2 \
    GH_HOST=example.invalid GH_CONFIG_DIR="$AUTH_HOME/host-config" GH_HTTP_UNIX_SOCKET="$AUTH_HOME/socket" \
    GIT_CONFIG="${INJECT_GIT_CONFIG-}" GIT_CONFIG_PARAMETERS="${INJECT_PARAMETERS-}" \
    GIT_CONFIG_COUNT="${INJECT_COUNT-}" GIT_CONFIG_KEY_0="${INJECT_KEY_0-}" \
    GIT_CONFIG_VALUE_0="${INJECT_VALUE_0-}" \
    "$WRAPPER" "$@") > "$stdout" 2> "$stderr"
  GH_STATUS=$?
  set -e
  GH_STDOUT="$(< "$stdout")"
  GH_STDERR="$(< "$stderr")"
}

reset_bundle_read_canary() {
  CANARY_BUNDLES=(
    "$AUTH_HOME/.config/dotfiles/local/secrets/github-MatthewssSmith1.env"
    "$AUTH_HOME/.config/dotfiles/local/secrets/github-mimir-db.env"
  )
  for CANARY_BUNDLE in "${CANARY_BUNDLES[@]}"; do
    printf 'GH_TOKEN=%s\n' "$FIXTURE_TOKEN" > "$CANARY_BUNDLE"
    chmod 0600 "$CANARY_BUNDLE"
    touch -a -d @1 "$CANARY_BUNDLE"
  done
}

assert_bundle_not_read() {
  for CANARY_BUNDLE in "${CANARY_BUNDLES[@]}"; do
    [[ "$(stat -c %X -- "$CANARY_BUNDLE")" == 1 ]] || fail 'rejected/tokenless invocation read a token bundle'
  done
}

captured_args() {
  mapfile -d '' -t CAPTURED_ARGS < "$CAPTURE_DIR/args"
}

assert_status() {
  ((GH_STATUS == $1)) || fail "expected status $1, got $GH_STATUS: $GH_STDERR"
}

# Final payloads are exact, executable, Bash-valid, and Ubuntu-only by topology.
[[ "$(stat -c %a -- "$WRAPPER_SOURCE")" == 755 && "$(stat -c %a -- "$HELPER")" == 755 ]] || fail 'GitHub executables have wrong modes'
grep -qxF 'BACKEND=/usr/bin/gh' "$WRAPPER_SOURCE" || fail 'production gh backend is not fixed'
bash -n "$WRAPPER_SOURCE" "$HELPER" || fail 'GitHub executables have invalid syntax'
[[ -f "$REPO_DIR/packages/ubuntu/git/.config/dotfiles/git/github-vps.conf" &&
  ! -e "$REPO_DIR/packages/common/git/.local/bin/gh" &&
  ! -e "$REPO_DIR/packages/common/git/.config/dotfiles/git/github-vps.conf" ]] || fail 'GitHub payload topology is not Ubuntu-only'
pass

# Dormant mode exact-execs the backend with untouched arguments and environment.
new_auth_home dormant
write_bundles
reset_bundle_read_canary
INHERITED_REPO='host.example/owner/repo' INHERITED_TOKEN='parent-token' run_gh auth token 'two words' '*.literal'
assert_status 0
captured_args
[[ "${CAPTURED_ARGS[*]}" == 'auth token two words *.literal' ]] || fail 'dormant mode changed arguments'
grep -qxF 'GH_TOKEN=parent-token' "$CAPTURE_DIR/environment" || fail 'dormant mode sanitized GH_TOKEN'
grep -qxF 'GH_REPO=host.example/owner/repo' "$CAPTURE_DIR/environment" || fail 'dormant mode sanitized GH_REPO'
assert_bundle_not_read
pass

# Active marker must be one true value from the exact deployed path.
new_auth_home wrong-origin
printf '[dotfiles "github-vps"]\n\tenabled = true\n' > "$AUTH_HOME/.gitconfig"
run_gh --help
assert_status 77
assert_contains "$GH_STDERR" 'gh-vps-policy:'
[[ ! -e "$CAPTURE_DIR/args" ]] || fail 'wrong-origin activation reached backend'
new_auth_home malformed-marker
printf '[broken\n' > "$AUTH_HOME/.gitconfig"
run_gh --help
assert_status 77
pass

# Active help/version are policy-first and never require or read bundles.
new_auth_home help
activate
for args in '--help' 'help' 'pr --help' 'pr merge --help'; do
  reset_bundle_read_canary
  read -r -a words <<< "$args"
  run_gh "${words[@]}"
  assert_status 0
  [[ "$GH_STDOUT" == "MATT'S VPS GH POLICY"$'\n'* ]] || fail "policy help was not first: $args"
  assert_bundle_not_read
done
reset_bundle_read_canary
run_gh --version
assert_status 0
assert_contains "$GH_STDOUT" 'gh-vps-policy: Matt'
[[ "$GH_STDOUT$GH_STDERR" != *"$FIXTURE_TOKEN"* ]] || fail 'help/version exposed a token'
assert_bundle_not_read
pass

# Marker discovery ignores every inherited Git config injection route.
INJECT_COUNT=1 INJECT_KEY_0=dotfiles.github-vps.enabled INJECT_VALUE_0=false run_gh --help
assert_status 0
INJECT_PARAMETERS="'dotfiles.github-vps.enabled=false'" run_gh --version
assert_status 0
unset INJECT_COUNT INJECT_KEY_0 INJECT_VALUE_0 INJECT_PARAMETERS
pass

# Credential routing accepts both canonical owners case-insensitively.
new_auth_home credential
write_bundles
for path in MatthewssSmith1/dotfiles MatthewssSmith1/dotfiles.git matthewsssmith1/dotfiles mimir-db/mimir-db MIMIR-DB/mimir-db-v0; do
  output="$(printf 'protocol=https\nhost=github.com\npath=%s\n\n' "$path" | HOME="$AUTH_HOME" "$HELPER" get)"
  [[ "$output" == $'username=x-access-token\npassword='"$FIXTURE_TOKEN" ]] || fail "credential route failed: $path"
done
for input in \
  $'protocol=http\nhost=github.com\npath=MatthewssSmith1/dotfiles\n' \
  $'protocol=https\nhost=example.com\npath=MatthewssSmith1/dotfiles\n' \
  $'protocol=https\nhost=github.com\npath=unknown/repo\n' \
  $'protocol=https\nhost=github.com\npath=MatthewssSmith1/not-selected\n' \
  $'protocol=https\nprotocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n' \
  $'protocol=https\nhost=github.com\npath=https://github.com/MatthewssSmith1/dotfiles\n'; do
  [[ "$(printf '%s\n' "$input" | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'unsafe credential route did not quit'
done
oversized="$(printf 'x%.0s' {1..65536})"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\nextra=%s\n\n' "$oversized" | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'oversized credential protocol input was accepted'
pass

# Bundle contract is exact-one nonempty GH_TOKEN and rejects unsafe objects/data.
bundle="$AUTH_HOME/.config/dotfiles/local/secrets/github-MatthewssSmith1.env"
for content in $'GH_TOKEN=\n' $'GH_TOKEN=one\nGH_TOKEN=two\n' $'GH_TOKEN=one\nPATH=/tmp\n'; do
  printf '%s' "$content" > "$bundle"; chmod 0600 "$bundle"
  [[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'malformed exact-token bundle was accepted'
done
printf 'GH_TOKEN=bad\rvalue\n' > "$bundle"; chmod 0600 "$bundle"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'control-byte bundle was accepted'
printf '# owner token\n\nGH_TOKEN=%s\n\n' "$FIXTURE_TOKEN" > "$bundle"; chmod 0600 "$bundle"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == $'username=x-access-token\npassword='"$FIXTURE_TOKEN" ]] || fail 'documented comments and blank lines were rejected'
printf 'GH_TOKEN=%s\n' "$FIXTURE_TOKEN" > "$bundle"; chmod 0644 "$bundle"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'broad bundle mode was accepted'
mv "$bundle" "$TEST_ROOT/outside-bundle"; ln -s "$TEST_ROOT/outside-bundle" "$bundle"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'linked bundle was accepted'
new_auth_home unsafe-parent
write_bundles
chmod 0775 "$AUTH_HOME/.config/dotfiles/local"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'writable bundle parent was accepted'
chmod 0755 "$AUTH_HOME/.config/dotfiles/local"
mv "$AUTH_HOME/.config/dotfiles/local/secrets" "$AUTH_HOME/real-secrets"
ln -s "$AUTH_HOME/real-secrets" "$AUTH_HOME/.config/dotfiles/local/secrets"
[[ "$(printf 'protocol=https\nhost=github.com\npath=MatthewssSmith1/dotfiles\n\n' | HOME="$AUTH_HOME" "$HELPER" get)" == 'quit=1' ]] || fail 'linked secrets directory was accepted'
pass

# Store consumes input; erase is non-destructive; unknown operations are silent.
before="$(sha256sum "$TEST_ROOT/outside-bundle")"
printf 'secret=input\n\n' | HOME="$AUTH_HOME" "$HELPER" store
if printf 'secret=input\n\n' | HOME="$AUTH_HOME" "$HELPER" erase > "$CAPTURE_DIR/erase.out" 2> "$CAPTURE_DIR/erase.err"; then fail 'erase succeeded'; fi
assert_contains "$(< "$CAPTURE_DIR/erase.err")" 'rotate the PAT'
printf 'secret=input\n\n' | HOME="$AUTH_HOME" "$HELPER" future-operation
[[ "$(sha256sum "$TEST_ROOT/outside-bundle")" == "$before" ]] || fail 'credential operation changed a bundle'
pass

# Allowed commands validate before bundle loading and preserve exact argv.
new_auth_home allowed
activate
write_bundles
INHERITED_REPO='MatthewssSmith1/dotfiles' run_gh pr list --author matt --json number,title --jq '.[]'
assert_status 0
captured_args
[[ "${CAPTURED_ARGS[*]}" == 'pr list --author matt --json number,title --jq .[]' ]] || fail 'list argv changed'
run_gh pr view 11 -R MatthewssSmith1/dotfiles --json number
assert_status 0
INHERITED_REPO='mimir-db/mimir-db' run_gh pr view 42 --comments --json headRefOid
assert_status 0
INHERITED_REPO='mimir-db/mimir-db' run_gh pr status --conflict-status --json currentBranch
assert_status 0
INHERITED_REPO='mimir-db/mimir-db-v0' run_gh pr diff 42 --patch
assert_status 0
run_gh pr create --repo=mimir-db/mimir-db --title title --body 'two words' --draft --reviewer matt
assert_status 0
sha=0123456789abcdef0123456789abcdef01234567
run_gh pr merge 42 --rebase --match-head-commit "$sha" --repo mimir-db/mimir-db --subject reviewed
assert_status 0
captured_args
[[ "${CAPTURED_ARGS[*]}" == "pr merge 42 --rebase --match-head-commit $sha --repo mimir-db/mimir-db --subject reviewed" ]] || fail 'merge argv changed'
pass

# Rejected families, flags, and malformed native values fail before bundle access.
reset_bundle_read_canary
for args in 'api user' 'auth status' 'repo view' 'pr create --repo mimir-db/mimir-db --dry-run' \
  'pr view --web' 'pr merge 42 --merge --match-head-commit 0123456789abcdef0123456789abcdef01234567 --repo mimir-db/mimir-db' \
  'pr merge 42 --squash --admin --match-head-commit 0123456789abcdef0123456789abcdef01234567 --repo mimir-db/mimir-db' \
  'pr merge 42 --squash --delete-branch --match-head-commit 0123456789abcdef0123456789abcdef01234567 --repo mimir-db/mimir-db'; do
  read -r -a words <<< "$args"
  run_gh "${words[@]}"
  assert_status 77
  assert_contains "$GH_STDERR" 'gh-vps-policy:'
  assert_bundle_not_read
done
for args in 'pr view not-a-number' 'pr merge 42 --repo mimir-db/mimir-db' \
  'pr merge 42 --squash --rebase --match-head-commit 0123456789abcdef0123456789abcdef01234567 --repo mimir-db/mimir-db' \
  'pr merge 42 --squash --match-head-commit short --repo mimir-db/mimir-db' \
  'pr create --title missing-repo' 'pr list --limit nope' 'pr list --state invalid' \
  'pr diff --color invalid' 'pr list --jq . -R MatthewssSmith1/dotfiles' \
  'pr list --template x -R MatthewssSmith1/dotfiles' \
  'pr list --json number --json title -R MatthewssSmith1/dotfiles' \
  'pr list -L 1 --limit 2 -R MatthewssSmith1/dotfiles' \
  'pr create --repo MatthewssSmith1/dotfiles --body one -b two' \
  'pr create --repo MatthewssSmith1/dotfiles --fill --fill-first' \
  'pr diff --name-only --patch -R MatthewssSmith1/dotfiles'; do
  read -r -a words <<< "$args"
  run_gh "${words[@]}"
  assert_status 64
  assert_bundle_not_read
done
pass

# Explicit and inherited repository routes reject duplicates/conflicts and bad forms.
write_bundles
run_gh pr view 1 -R MatthewssSmith1/dotfiles --repo=mimir-db/mimir-db
assert_status 64
INHERITED_REPO='mimir-db/mimir-db' run_gh pr view 1 -R MatthewssSmith1/dotfiles
assert_status 64
for repo in github.com/MatthewssSmith1/dotfiles https://github.com/MatthewssSmith1/dotfiles git@github.com:MatthewssSmith1/dotfiles; do
  INHERITED_REPO='' run_gh pr view 1 --repo "$repo"
  assert_status 64
done
for repo in unknown/repo MatthewssSmith1/not-selected; do
  INHERITED_REPO='' run_gh pr view 1 --repo "$repo"
  assert_status 77
done
pass

# Checkout discovery works in subdirectories and rejects noncanonical/ambiguous origins.
checkout="$TEST_ROOT/checkout"
mkdir -p "$checkout/subdir"
git -C "$checkout" init -q
git -C "$checkout" remote add origin https://github.com/MatthewssSmith1/dotfiles.git
RUN_CWD="$checkout/subdir" INHERITED_REPO='' run_gh pr view 7 --json headRefOid
assert_status 0
grep -qxF 'GH_REPO=MatthewssSmith1/dotfiles' "$CAPTURE_DIR/environment" || fail 'checkout repository was not normalized'
INJECT_COUNT=1 INJECT_KEY_0=url.https://injected.invalid/.insteadOf INJECT_VALUE_0=https://github.com/ \
  RUN_CWD="$checkout/subdir" INHERITED_REPO='' run_gh pr view 7
assert_status 0
unset INJECT_COUNT INJECT_KEY_0 INJECT_VALUE_0
git -C "$checkout" remote set-url origin git@github.com:MatthewssSmith1/dotfiles.git
RUN_CWD="$checkout" INHERITED_REPO='' run_gh pr view 7
assert_status 77
git -C "$checkout" config url.https://github.com/.insteadOf gh:
git -C "$checkout" remote set-url origin gh:MatthewssSmith1/dotfiles.git
RUN_CWD="$checkout" INHERITED_REPO='' run_gh pr view 7
assert_status 77
git -C "$checkout" config --unset-all url.https://github.com/.insteadOf
git -C "$checkout" remote set-url origin https://github.com/MatthewssSmith1/dotfiles.git
git -C "$checkout" config url.https://mirror.invalid/.insteadOf https://github.com/
RUN_CWD="$checkout" INHERITED_REPO='' run_gh pr view 7
assert_status 77
git -C "$checkout" config --unset-all url.https://mirror.invalid/.insteadOf
git -C "$checkout" config url.https://push.invalid/.pushInsteadOf https://github.com/
RUN_CWD="$checkout" INHERITED_REPO='' run_gh pr view 7
assert_status 77
git -C "$checkout" config --unset-all url.https://push.invalid/.pushInsteadOf
git -C "$checkout" remote set-url --push origin https://github.com/mimir-db/mimir-db.git
RUN_CWD="$checkout" INHERITED_REPO='' run_gh pr view 7
assert_status 77
git -C "$checkout" config --unset-all remote.origin.pushurl
git -C "$checkout" remote set-url --add origin https://github.com/mimir-db/mimir-db.git
RUN_CWD="$checkout" INHERITED_REPO='' run_gh pr view 7
assert_status 77
unset RUN_CWD
pass

# Active execution removes inherited routing, selects one token, and preserves streams/status.
INJECT_GIT_CONFIG="$AUTH_HOME/hostile-config" INJECT_PARAMETERS="'credential.helper=hostile'" \
  INJECT_COUNT=1 INJECT_KEY_0=url.https://invalid/.insteadOf INJECT_VALUE_0=https://github.com/ \
  INHERITED_REPO='mimir-db/mimir-db' INHERITED_TOKEN='hostile-parent-token' BACKEND_STATUS=42 \
  run_gh pr view 9 --json number <<< 'stream-input'
unset INJECT_GIT_CONFIG INJECT_PARAMETERS INJECT_COUNT INJECT_KEY_0 INJECT_VALUE_0
assert_status 42
grep -qxF "GH_TOKEN=$FIXTURE_TOKEN" "$CAPTURE_DIR/environment" || fail 'selected token was not exported'
grep -qxF 'GH_REPO=mimir-db/mimir-db' "$CAPTURE_DIR/environment" || fail 'normalized repository was not exported'
grep -qxF 'GH_HOST=github.com' "$CAPTURE_DIR/environment" || fail 'fixed GitHub host was not exported'
for variable in GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR GH_HTTP_UNIX_SOCKET; do
  ! grep -q "^$variable=" "$CAPTURE_DIR/environment" || fail "$variable survived sanitization"
done
for variable in GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
  ! grep -q "^$variable=" "$CAPTURE_DIR/environment" || fail "$variable survived sanitization"
done
[[ "$(< "$CAPTURE_DIR/stdin")" == stream-input ]] || fail 'stdin was not preserved'
assert_contains "$GH_STDOUT" native-output
assert_contains "$GH_STDERR" native-error
[[ "$GH_STDOUT$GH_STDERR" != *"$FIXTURE_TOKEN"* && "$GH_STDOUT$GH_STDERR" != *hostile-parent-token* ]] || fail 'diagnostics exposed a token'
! HOME="$AUTH_HOME" git -C "$checkout" config --includes --list | grep -q "$FIXTURE_TOKEN" || fail 'token entered Git config'
! git -C "$checkout" remote -v | grep -q "$FIXTURE_TOKEN" || fail 'token entered checkout remotes'
(cd "$AUTH_HOME" && HOME="$AUTH_HOME" CAPTURE_DIR="$CAPTURE_DIR" GH_REPO=mimir-db/mimir-db \
  bash -x "$WRAPPER" pr view 9 --json number) > "$CAPTURE_DIR/xtrace.out" 2> "$CAPTURE_DIR/xtrace.err"
[[ "$(< "$CAPTURE_DIR/xtrace.out")$(< "$CAPTURE_DIR/xtrace.err")" != *"$FIXTURE_TOKEN"* ]] || fail 'token entered shell xtrace'
pass

# Missing, linked, copied, and hardlinked recursive backends fail closed.
mv "$backend_root/usr/bin/gh" "$backend_root/usr/bin/gh.real"
ln -s gh.real "$backend_root/usr/bin/gh"
INHERITED_REPO='MatthewssSmith1/dotfiles' run_gh pr view 1
assert_status 77
assert_contains "$GH_STDERR" 'fixed /usr/bin/gh backend is unavailable'
rm "$backend_root/usr/bin/gh"
INHERITED_REPO='MatthewssSmith1/dotfiles' run_gh pr view 1
assert_status 77
cp "$WRAPPER" "$backend_root/usr/bin/gh"
chmod 0755 "$backend_root/usr/bin/gh"
INHERITED_REPO='MatthewssSmith1/dotfiles' run_gh pr view 1
assert_status 77
assert_contains "$GH_STDERR" 'policy launcher'
rm "$backend_root/usr/bin/gh"
ln "$WRAPPER" "$backend_root/usr/bin/gh"
INHERITED_REPO='MatthewssSmith1/dotfiles' run_gh pr view 1
assert_status 77
assert_contains "$GH_STDERR" 'policy launcher'
pass

printf 'PASS: %d GitHub authentication test groups\n' "$TEST_COUNT"
