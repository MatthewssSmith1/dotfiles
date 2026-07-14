#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
readonly BOOTSTRAP="$REPO_DIR/bootstrap.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$BOOTSTRAP" || fail 'bootstrap.sh has invalid Bash syntax'

grep -q '((EUID != 0))' "$BOOTSTRAP" || fail 'bootstrap does not use the shell EUID for root refusal'
grep -q -- '--target="$HOME"' "$BOOTSTRAP" || fail 'Stow does not explicitly target HOME'

if grep -Eq '(^|[^[:alnum:]_])(sudo|apt-get|usermod|chsh)([^[:alnum:]_]|$)|/etc/shells' "$BOOTSTRAP"; then
  fail 'bootstrap.sh contains a privileged package or login-shell operation'
fi

temp_home="$(mktemp -d)"
flow_root="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temp_home"
  rm -rf -- "$flow_root"
}
trap cleanup EXIT

check_output="$(HOME="$temp_home" "$BOOTSTRAP" --check 2>&1)" || {
  printf '%s\n' "$check_output" >&2
  fail 'bootstrap preflight failed on this system'
}
[[ "$check_output" == *'no changes made'* ]] || \
  fail 'bootstrap preflight did not confirm its non-mutating behavior'
shopt -s nullglob dotglob
home_entries=("$temp_home"/*)
((${#home_entries[@]} == 0)) || fail 'bootstrap preflight modified HOME'

if HOME="$temp_home" "$BOOTSTRAP" --unknown >/dev/null 2>&1; then
  fail 'bootstrap accepted an unknown argument'
fi

if command -v unshare >/dev/null 2>&1 && unshare --user --map-root-user true 2>/dev/null; then
  if unshare --user --map-root-user env HOME="$temp_home" "$BOOTSTRAP" --check >/dev/null 2>&1; then
    fail 'bootstrap did not refuse effective UID 0'
  fi
fi

conflict_root="$(mktemp -d)"
cp -a "$REPO_DIR/." "$conflict_root/dotfiles"
mkdir "$conflict_root/home"
printf 'unmanaged\n' > "$conflict_root/home/.zshrc"
conflict_output="$(HOME="$conflict_root/home" "$conflict_root/dotfiles/bootstrap.sh" 2>&1)" && \
  fail 'bootstrap accepted an unmanaged Stow conflict'
[[ "$conflict_output" == *'Stow conflict preflight failed'* ]] || \
  fail 'bootstrap did not report the Stow conflict clearly'
[[ "$(cat "$conflict_root/home/.zshrc")" == 'unmanaged' ]] || \
  fail 'bootstrap changed the conflicting unmanaged file'
[[ ! -e "$conflict_root/home/.local" && ! -e "$conflict_root/home/.gitconfig.local" ]] || \
  fail 'bootstrap mutated HOME before detecting the Stow conflict'
rm -rf -- "$conflict_root"

fake_bin="$flow_root/bin"
flow_home="$flow_root/home"
mkdir -p "$fake_bin" "$flow_home/.opencode/auth"

for command_name in fd gh mise node pnpm claude opencode wt vp zoxide stow; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/$command_name"
  chmod +x "$fake_bin/$command_name"
done
cat > "$fake_bin/nvim" <<'EOF'
#!/usr/bin/env bash
printf 'NVIM v0.11.0\n'
EOF
chmod +x "$fake_bin/nvim"
cat > "$fake_bin/npx" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$flow_root/npx.log"
EOF
chmod +x "$fake_bin/npx"
cat > "$fake_bin/mise" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$flow_root/mise.log"
EOF
chmod +x "$fake_bin/mise"

printf '{"credential":"preserve-me"}\n' > "$flow_home/.opencode/auth/openai.json"
auth_checksum="$(sha256sum "$flow_home/.opencode/auth/openai.json")"

HOME="$flow_home" BOOTSTRAP_TEST_BIN="$fake_bin" \
  GIT_USER_NAME='Test User' GIT_USER_EMAIL='test.user@example.com' \
  "$BOOTSTRAP" >/dev/null
[[ "$(git config --file "$flow_home/.gitconfig.local" --get user.name)" == 'Test User' ]] || \
  fail 'bootstrap did not configure Git user.name'
[[ "$(git config --file "$flow_home/.gitconfig.local" --get user.email)" == 'test.user@example.com' ]] || \
  fail 'bootstrap did not configure Git user.email'
[[ "$(stat -c %a "$flow_home/.gitconfig.local")" == '600' ]] || \
  fail 'bootstrap did not protect local Git identity'
[[ "$(cat "$flow_root/npx.log")" == '-y opencode-openai-codex-auth@latest' ]] || \
  fail 'bootstrap did not run the exact OpenCode plugin installer command'
[[ "$(cat "$flow_root/mise.log")" == *'zoxide@latest'* ]] || \
  fail 'bootstrap did not install zoxide through mise'
[[ "$(sha256sum "$flow_home/.opencode/auth/openai.json")" == "$auth_checksum" ]] || \
  fail 'bootstrap changed existing OpenCode authentication state'

identity_checksum="$(sha256sum "$flow_home/.gitconfig.local")"
HOME="$flow_home" BOOTSTRAP_TEST_BIN="$fake_bin" \
  GIT_USER_NAME='Different User' GIT_USER_EMAIL='different@example.com' \
  "$BOOTSTRAP" >/dev/null
[[ "$(sha256sum "$flow_home/.gitconfig.local")" == "$identity_checksum" ]] || \
  fail 'bootstrap overwrote an established Git identity on rerun'
[[ "$(sha256sum "$flow_home/.opencode/auth/openai.json")" == "$auth_checksum" ]] || \
  fail 'bootstrap changed OpenCode authentication state on rerun'
[[ "$(wc -l < "$flow_root/npx.log")" == '2' ]] || \
  fail 'bootstrap did not converge the OpenCode plugin configuration on each run'

placeholder_home="$flow_root/placeholder-home"
mkdir "$placeholder_home"
cp "$REPO_DIR/.gitconfig.local.example" "$placeholder_home/.gitconfig.local"
HOME="$placeholder_home" BOOTSTRAP_TEST_BIN="$fake_bin" \
  GIT_USER_NAME="Test O'Neil" GIT_USER_EMAIL='oneil@example.com' \
  "$BOOTSTRAP" >/dev/null
[[ "$(git config --file "$placeholder_home/.gitconfig.local" --get user.name)" == "Test O'Neil" ]] || \
  fail 'bootstrap did not replace the Git identity placeholder safely'

missing_home="$flow_root/missing-home"
mkdir "$missing_home"
if HOME="$missing_home" BOOTSTRAP_TEST_BIN="$fake_bin" "$BOOTSTRAP" >/dev/null 2>&1; then
  fail 'bootstrap accepted a missing Git identity without explicit values'
fi

if grep -q 'opencode auth login' "$BOOTSTRAP"; then
  fail 'bootstrap attempts interactive OpenCode authentication'
fi
if grep -Eq -- '--uninstall|--all' "$BOOTSTRAP"; then
  fail 'bootstrap contains a destructive OpenCode plugin installer flag'
fi
mise_line="$(grep -n 'mise activate zsh' "$REPO_DIR/.zshrc" | cut -d: -f1)"
zoxide_line="$(grep -n 'zoxide init' "$REPO_DIR/.zshrc" | cut -d: -f1)"
((mise_line < zoxide_line)) || fail 'zoxide initializes before mise activation'

printf 'PASS: bootstrap boundary, identity, and tool checks\n'
