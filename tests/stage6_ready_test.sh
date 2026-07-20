#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_REPO_DIR="$(cd -- "$TEST_DIR/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
cp -a "$SOURCE_REPO_DIR/." "$TEST_ROOT/repo/"
sed -i 's/^area|tmux|ready$/area|tmux|framework/; s/^area|nvim|ready$/area|nvim|framework/' \
  "$TEST_ROOT/repo/manifests/areas.tsv"
readonly REPO_DIR="$TEST_ROOT/repo"

fail() { printf 'FAIL: %s\n%s\n' "$*" "${TEST_OUTPUT:-}" >&2; exit 1; }

home="$TEST_ROOT/home"
host="$TEST_ROOT/host"
distro_bin="$TEST_ROOT/distro-bin"
sentinel_bin="$TEST_ROOT/sentinel-bin"
mkdir -p "$home/.config/opencode" "$home/.local/bin" \
  "$home/.local/state/dotfiles/provisioning/v1" \
  "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0" \
  "$home/.local/share/mise/installs/aqua-starship-starship" \
  "$host/etc" "$host/proc/sys/kernel" "$distro_bin" "$sentinel_bin"
printf 'ID=ubuntu\nVERSION_ID=24.04\n' > "$host/etc/os-release"
printf '6.6.0-microsoft-standard-WSL2\n' > "$host/proc/sys/kernel/osrelease"
printf 'preserved OpenCode fixture\n' > "$home/.config/opencode/opencode.json"

for name in curl wget ssh scp sudo apt apt-get pacman dnf yum apk snap flatpak npm pnpm yarn bun pip pip3; do
  cat > "$sentinel_bin/$name" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s:%s\n' "${0##*/}" "$*" >> "$HOME/network-attempted"
exit 97
SCRIPT
  chmod 0755 "$sentinel_bin/$name"
done
cat > "$sentinel_bin/git" <<'SCRIPT'
#!/usr/bin/env bash
case " ${*:-} " in
  *' clone '*|*' fetch '*|*' pull '*|*' push '*|*' ls-remote '*|*' submodule '*)
    printf 'git:%s\n' "$*" >> "$HOME/network-attempted"
    exit 97
    ;;
esac
exec /usr/bin/git "$@"
SCRIPT
chmod 0755 "$sentinel_bin/git"
cat > "$sentinel_bin/chsh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'chsh:%s\n' "$*" >> "$HOME/chsh-attempted"
exit 97
SCRIPT
chmod 0755 "$sentinel_bin/chsh"

for name in fzf zoxide eza rg batcat fdfind; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$distro_bin/$name"
  chmod 0755 "$distro_bin/$name"
done
cat > "$TEST_ROOT/dpkg-query" <<'SCRIPT'
#!/usr/bin/env bash
case "$2" in
  */fzf) package=fzf ;; */zoxide) package=zoxide ;; */eza) package=eza ;; */rg) package=ripgrep ;;
  */batcat) package=bat ;; */fdfind) package=fd-find ;; *) exit 1 ;;
esac
printf '%s: %s\n' "$package" "$2"
SCRIPT
chmod 0755 "$TEST_ROOT/dpkg-query"

cat > "$home/.local/bin/mise" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf '2026.7.7 linux-x64\n' ;;
  activate) exit 0 ;;
  *) exit 1 ;;
esac
SCRIPT
cat > "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship" <<'SCRIPT'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && printf 'starship 1.26.0\n'
SCRIPT
chmod 0755 "$home/.local/bin/mise" \
  "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship"
ln -s "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0" \
  "$home/.local/share/mise/installs/aqua-starship-starship/1.26.0"
launcher_content="#!/usr/bin/env bash
exec $home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship \"\$@\""
printf '%s\n' "$launcher_content" > "$home/.local/bin/starship"
chmod 0755 "$home/.local/bin/starship"
mise_hash="$(sha256sum "$home/.local/bin/mise")"; mise_hash="${mise_hash%% *}"
tool_hash="$(sha256sum "$home/.local/share/dotfiles/provisioning/tools/starship/1.26.0/starship")"; tool_hash="${tool_hash%% *}"
launcher_hash="$(printf '%s\n' "$launcher_content" | sha256sum)"; launcher_hash="${launcher_hash%% *}"
manifest_hash="$(sha256sum "$REPO_DIR/manifests/provisioning.json")"; manifest_hash="${manifest_hash%% *}"
jq -cn --arg manifest "$manifest_hash" --arg mise_hash "$mise_hash" --arg tool_hash "$tool_hash" \
  --arg launcher_hash "$launcher_hash" '
  {schema_version:1,manifest_sha256:$manifest,
   tools:[
     {id:"mise",backend:"bootstrap:mise",version:"2026.7.7",platform:"linux-x86_64",
      install_root:".local/bin",executable:"mise",executable_sha256:$mise_hash},
     {id:"starship",backend:"aqua:starship/starship",version:"1.26.0",platform:"linux-x86_64",
      install_root:".local/share/dotfiles/provisioning/tools/starship/1.26.0",executable:"starship",
      executable_sha256:$tool_hash}],
   launchers:[{tool_id:"starship",destination:".local/bin/starship",content_sha256:$launcher_hash}]}' \
  > "$home/.local/state/dotfiles/provisioning/v1/receipt.json"
chmod 0600 "$home/.local/state/dotfiles/provisioning/v1/receipt.json"

cp -a "$home" "$TEST_ROOT/home-before"
run_check() {
  HOME="$home" PATH="$home/.local/bin:$distro_bin:$sentinel_bin:/usr/bin:/bin" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" DOTFILES_TEST_ARCH=x86_64 \
    DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/dpkg-query" \
    GIT_USER_NAME='Ready Fixture' GIT_USER_EMAIL=ready@example.com \
    "$REPO_DIR/bootstrap.sh" --check "$@"
}
run_apply() {
  HOME="$home" PATH="$home/.local/bin:$distro_bin:$sentinel_bin:/usr/bin:/bin" \
    DOTFILES_TESTING=1 DOTFILES_TEST_HOST_ROOT="$host" DOTFILES_TEST_ARCH=x86_64 \
    DOTFILES_TEST_BASH_DISTRO_BIN="$distro_bin" DOTFILES_TEST_DPKG_QUERY="$TEST_ROOT/dpkg-query" \
    GIT_USER_NAME='Ready Fixture' GIT_USER_EMAIL=ready@example.com \
    "$REPO_DIR/bootstrap.sh" "$@"
}

login_shell_before="$(getent passwd "$(id -un)" | cut -d: -f7)"

TEST_OUTPUT="$(run_check --area bash 2>&1)" || fail 'explicit ready Bash check failed'
[[ "$TEST_OUTPUT" == *"area 'bash' preflight passed"* ]] || fail 'explicit Bash check did not pass its area preflight'
TEST_OUTPUT="$(run_check --area zsh 2>&1)" || fail 'explicit ready zsh check failed'
[[ "$TEST_OUTPUT" == *"area 'zsh' preflight passed"* ]] || fail 'explicit zsh check did not pass its area preflight'
TEST_OUTPUT="$(run_check 2>&1)" || fail 'default ready-area check failed'
for area in git bash zsh; do
  [[ "$TEST_OUTPUT" == *"area '$area' preflight passed"* ]] || fail "default check omitted ready area $area"
done
[[ "$TEST_OUTPUT" != *"area 'tmux'"* && "$TEST_OUTPUT" != *"area 'nvim'"* ]] || \
  fail 'default check selected a framework area'
[[ ! -e "$home/network-attempted" ]] || fail 'ready-area checks invoked a network sentinel'
HOME_DIFF="$(diff --no-dereference -r "$home" "$TEST_ROOT/home-before" || true)"
[[ -z "$HOME_DIFF" ]] || { TEST_OUTPUT="$HOME_DIFF"; fail 'ready-area checks mutated fixture HOME'; }

# First-time WSL rollout is explicitly Bash-first and zsh requires a later command.
cp -a "$home" "$TEST_ROOT/home-before-sequence"
set +e
TEST_OUTPUT="$(run_apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 ]] || fail 'first default WSL apply migrated Bash and zsh together'
[[ "$TEST_OUTPUT" == *'first WSL Bash deployment must explicitly select --area bash without zsh'* ]] || \
  fail 'first default WSL refusal did not explain Bash-first sequencing'
HOME_DIFF="$(diff --no-dereference -r "$home" "$TEST_ROOT/home-before-sequence" || true)"
[[ -z "$HOME_DIFF" ]] || { TEST_OUTPUT="$HOME_DIFF"; fail 'first default WSL refusal mutated HOME'; }

run_apply --area bash >/dev/null || fail 'explicit first Bash apply failed'
[[ -f "$home/.local/state/dotfiles/v1/bash.json" && ! -e "$home/.local/state/dotfiles/v1/zsh.json" ]] || \
  fail 'explicit first Bash apply did not stop before zsh'

# A state file alone is not a recovery guarantee: first zsh apply rechecks Bash links,
# attachments, controlled startup, and ownership health before any zsh mutation.
mv "$home/.config/dotfiles/bash/rc.bash" "$home/.config/dotfiles/bash/rc.bash.degraded-link"
printf 'unrelated replacement\n' > "$home/.config/dotfiles/bash/rc.bash"
set +e
TEST_OUTPUT="$(run_apply --area zsh 2>&1)"
status=$?
set -e
[[ "$status" != 0 && "$TEST_OUTPUT" == *'existing Bash deployment is degraded'* ]] || \
  fail 'first zsh apply accepted a degraded Bash deployment'
[[ "$(< "$home/.config/dotfiles/bash/rc.bash")" == 'unrelated replacement' && \
  ! -e "$home/.local/state/dotfiles/v1/zsh.json" ]] || \
  fail 'degraded Bash refusal mutated the replacement or started zsh migration'
rm "$home/.config/dotfiles/bash/rc.bash"
mv "$home/.config/dotfiles/bash/rc.bash.degraded-link" "$home/.config/dotfiles/bash/rc.bash"
set +e
TEST_OUTPUT="$(run_apply 2>&1)"
status=$?
set -e
[[ "$status" != 0 && "$TEST_OUTPUT" == *'first WSL zsh deployment must explicitly select --area zsh without bash'* ]] || \
  fail 'default apply deployed first-time zsh without an explicit second step'
run_apply --area zsh >/dev/null || fail 'explicit post-Bash zsh apply failed'
[[ -f "$home/.local/state/dotfiles/v1/zsh.json" ]] || fail 'explicit zsh apply did not record zsh state'
run_apply >/dev/null || fail 'later default apply failed after both shell areas were deployed'
run_apply --remove >/dev/null || fail 'ready-area fixture removal failed'

# A real WSL host with an explicit generic profile deploys and starts without the WSL adapter.
run_apply --profile generic --area bash >/dev/null || fail 'explicit generic-on-WSL Bash apply failed'
: > "$home/generic-trace"
HOME="$home" PATH="$home/.local/bin:$distro_bin:$sentinel_bin:/usr/bin:/bin" TERM=dumb HISTFILE=/dev/null \
  DOTFILES_BASH_TRACE="$home/generic-trace" bash --noprofile -i -c ':' >/dev/null 2> "$home/generic-stderr"
[[ "$(grep -c '^generic$' "$home/generic-trace")" == 1 && \
  "$(grep -c '^wsl$' "$home/generic-trace" || true)" == 0 ]] || \
  fail 'explicit generic-on-WSL startup loaded the WSL adapter or omitted generic startup'
run_apply --remove --area bash >/dev/null || fail 'explicit generic-on-WSL Bash removal failed'

login_shell_after="$(getent passwd "$(id -un)" | cut -d: -f7)"
[[ "$login_shell_after" == "$login_shell_before" ]] || fail 'login-shell value changed across check/apply/reapply/remove'
[[ ! -e "$home/chsh-attempted" ]] || fail 'ready-area lifecycle invoked chsh'

printf 'PASS: ready checks and guarded WSL shell rollout are offline and safe\n'
