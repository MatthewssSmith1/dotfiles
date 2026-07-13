#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
BOOTSTRAP_STEP="initialization"
TEMP_FILES=()

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] error: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

cleanup() {
  local file
  for file in "${TEMP_FILES[@]}"; do
    rm -f -- "$file"
  done
}

on_error() {
  local exit_code=$?
  printf '[%s] error: %s failed (line %s)\n' \
    "$SCRIPT_NAME" "$BOOTSTRAP_STEP" "${BASH_LINENO[0]}" >&2
  exit "$exit_code"
}

trap cleanup EXIT
trap on_error ERR

[[ -n "${HOME:-}" && -d "$HOME" ]] || die 'HOME must refer to an existing directory'
[[ "$(id -u)" -ne 0 ]] || die 'run bootstrap as the non-root workstation user'

# Keep system tools available even when an existing shell manager has changed PATH.
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

BOOTSTRAP_STEP="resolving the dotfiles directory"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly DOTFILES_DIR="$SCRIPT_DIR"

for required_file in \
  .gitconfig \
  .gitconfig.local.example \
  .stow-local-ignore \
  .zshrc; do
  [[ -f "$DOTFILES_DIR/$required_file" ]] || \
    die "expected $required_file next to $SCRIPT_NAME"
done

BOOTSTRAP_STEP="checking operating system support"
[[ -r /etc/os-release ]] || die 'cannot identify this operating system'
# shellcheck source=/dev/null
source /etc/os-release
case "${ID:-}" in
  ubuntu | debian) ;;
  *) die "unsupported operating system: ${PRETTY_NAME:-${ID:-unknown}} (Ubuntu or Debian required)" ;;
esac
command -v apt-get >/dev/null 2>&1 || die 'apt-get is required'

SUDO=()
if command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  die 'sudo is required to install system packages'
fi

if [[ ! -t 0 ]]; then
  BOOTSTRAP_STEP="checking non-interactive sudo access"
  "${SUDO[@]}" -n true || \
    die 'non-interactive bootstrap requires passwordless sudo access'
  SUDO+=(--non-interactive)
fi

BOOTSTRAP_STEP="installing system packages"
log 'Installing system packages'
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  ca-certificates \
  curl \
  fd-find \
  fzf \
  git \
  jq \
  ripgrep \
  stow \
  tmux \
  unzip \
  zsh

BOOTSTRAP_STEP="configuring fd"
mkdir -p "$HOME/.local/bin"
if ! command -v fd >/dev/null 2>&1; then
  fdfind_path="$(command -v fdfind || true)"
  [[ -n "$fdfind_path" ]] || die 'fd-find was installed but fdfind is unavailable'
  if [[ -e "$HOME/.local/bin/fd" || -L "$HOME/.local/bin/fd" ]]; then
    die "$HOME/.local/bin/fd exists but does not provide a working fd command"
  fi
  ln -s "$fdfind_path" "$HOME/.local/bin/fd"
fi

BOOTSTRAP_STEP="installing mise"
if command -v mise >/dev/null 2>&1; then
  MISE_BIN="$(command -v mise)"
else
  log 'Installing mise'
  mise_installer="$(mktemp)"
  TEMP_FILES+=("$mise_installer")
  curl --fail --silent --show-error --location https://mise.run --output "$mise_installer"
  MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$mise_installer"
  MISE_BIN="$HOME/.local/bin/mise"
fi
[[ -x "$MISE_BIN" ]] || die 'mise installation did not produce an executable'

readonly MISE_DATA_DIR="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
export PATH="$MISE_DATA_DIR/shims:$HOME/.local/bin:$PATH"

BOOTSTRAP_STEP="installing mise-managed tools"
log 'Installing versioned and personal tools with mise'
"$MISE_BIN" use --global \
  node@lts \
  pnpm@latest \
  neovim@latest \
  claude-code@latest \
  opencode@latest \
  worktrunk@latest
hash -r

BOOTSTRAP_STEP="installing Vite+"
if ! command -v vp >/dev/null 2>&1; then
  log 'Installing Vite+'
  vite_installer="$(mktemp)"
  TEMP_FILES+=("$vite_installer")
  curl --fail --silent --show-error --location https://vite.plus --output "$vite_installer"
  CI=1 VP_NODE_MANAGER=no bash "$vite_installer"
fi
export PATH="$MISE_DATA_DIR/shims:$HOME/.vite-plus/bin:$HOME/.local/bin:$PATH"
hash -r
command -v vp >/dev/null 2>&1 || die 'Vite+ installation did not provide vp'
vp env off

BOOTSTRAP_STEP="configuring local Git identity"
gitconfig_local="$HOME/.gitconfig.local"
if [[ -L "$gitconfig_local" && ! -e "$gitconfig_local" ]]; then
  die "$gitconfig_local is a broken symlink; repair it before rerunning bootstrap"
elif [[ -e "$gitconfig_local" ]]; then
  [[ -f "$gitconfig_local" ]] || die "$gitconfig_local exists but is not a regular file"
else
  cp "$DOTFILES_DIR/.gitconfig.local.example" "$gitconfig_local"
  chmod 0600 "$gitconfig_local"
  log "Created $gitconfig_local; replace its placeholder identity"
fi

BOOTSTRAP_STEP="applying dotfiles with Stow"
log 'Applying dotfiles with Stow'
(
  cd "$DOTFILES_DIR"
  stow_status=0
  stow_output="$(stow -R . 2>&1)" || stow_status=$?
  [[ -z "$stow_output" ]] || printf '%s\n' "$stow_output" >&2
  if [[ "$stow_output" == *'BUG in find_stowed_path'* ]]; then
    # Stow 2.3 reports success despite failing to scan unrelated WSL links.
    log 'Restow failed; retrying the same package without the removal pass'
    stow .
  elif ((stow_status != 0)); then
    exit "$stow_status"
  fi
)

BOOTSTRAP_STEP="configuring the login shell"
zsh_path="$(command -v zsh)"
zsh_is_allowed=false
while IFS= read -r shell_path; do
  if [[ "$shell_path" == "$zsh_path" ]]; then
    zsh_is_allowed=true
    break
  fi
done </etc/shells
[[ "$zsh_is_allowed" == true ]] || die "$zsh_path is not listed in /etc/shells"

current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"
[[ -n "$current_shell" ]] || die 'could not determine the current login shell'
if [[ "$current_shell" != "$zsh_path" ]]; then
  "${SUDO[@]}" usermod --shell "$zsh_path" "$(id -un)"
  log 'Changed the login shell to Zsh; start a new login session to use it'
fi

BOOTSTRAP_STEP="validating installed tools"
log 'Validating installed tools'
required_commands=(
  git zsh stow curl unzip make rg fd fzf jq tmux mise nvim node pnpm
  claude opencode wt vp
)
for required_command in "${required_commands[@]}"; do
  command -v "$required_command" >/dev/null 2>&1 || \
    die "required command is unavailable: $required_command"
done

nvim_version_output="$(nvim --version)"
nvim_version_line="${nvim_version_output%%$'\n'*}"
nvim_version="${nvim_version_line#NVIM }"
nvim_version="${nvim_version#v}"
[[ "$nvim_version" =~ ^[0-9]+\.[0-9]+ ]] || \
  die "could not parse Neovim version: $nvim_version_line"
nvim_major="${nvim_version%%.*}"
nvim_remainder="${nvim_version#*.}"
nvim_minor="${nvim_remainder%%.*}"
if ((nvim_major < 1 && nvim_minor < 11)); then
  die "Neovim 0.11 or newer is required; found $nvim_version"
fi

[[ -f "$gitconfig_local" ]] || die "$gitconfig_local is unavailable"
[[ ! -e "$HOME/bootstrap.sh" && ! -L "$HOME/bootstrap.sh" ]] || \
  die 'Stow unexpectedly created ~/bootstrap.sh'

log 'Bootstrap completed successfully'
