#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.sh"

export HOME="$(new_home nvim-provision)" SELECTED_PROFILE=ubuntu DOTFILES_DIR="$REPO_DIR"
export NVIM_SELECTOR='aqua:neovim/neovim@0.12.4' SCRIPT_NAME=nvim-provision-test
source "$REPO_DIR/lib/nvim-provision.sh"
log() { :; }
log_error() { printf '%s\n' "$*" >&2; }
die() { log_error "$*"; exit 1; }

# Exercise JavaScript semantics when a real compatible Node/npm is available.
# The package-manager fixtures below cannot catch invalid process.exit types.
if command -v node >/dev/null && command -v npm >/dev/null &&
  [[ "$(node -p 'Number(process.versions.node.split(".")[0]) >= 20')" == true ]] &&
  npm --version >/dev/null 2>&1; then
  nvim_provision_node_pair || fail 'real compatible Node/npm rejected'
  pass
fi

# Fake the package database, package manager, and runtime; no host installation.
NVIM_MISSING_PACKAGES=()
nvim_provision_missing_packages() { NVIM_MISSING_PACKAGES=(); [[ -e "$HOME/packages" ]] || NVIM_MISSING_PACKAGES=(git sqlite3); }
nvim_provision_command() { return 0; }
nvim_provision_mise() { printf '%s\n' "$HOME/mise-install"; }
nvim_provision_mise_node() { printf '%s\n' "$HOME/node-install"; }
nvim_provision_node_pair() {
  [[ -n "${1:-}" && -x "$1/bin/node" && -f "$1/bin/npm" ]] || [[ -e "$HOME/host-node" ]]
}
sudo() { printf 'sudo %s\n' "$*" >> "$HOME/trace"; touch "$HOME/packages"; }
mise() {
  printf 'mise %s\n' "$*" >> "$HOME/trace"
  if [[ "$1" == install && "$2" == "$NVIM_SELECTOR" ]]; then
    mkdir -p "$HOME/mise-install/bin"
    touch "$HOME/mise-install/bin/nvim"
    chmod +x "$HOME/mise-install/bin/nvim"
  elif [[ "$1" == install && "$2" == node@lts ]]; then
    mkdir -p "$HOME/node-install/bin"
    touch "$HOME/node-install/bin/node" "$HOME/node-install/bin/npm"
    chmod +x "$HOME/node-install/bin/node"
  fi
}

if validate_nvim_prerequisites >/dev/null 2>&1; then fail 'missing prerequisites passed check'; fi
[[ ! -e "$HOME/trace" && ! -e "$HOME/packages" ]] || fail 'check mutated host'
pass
nvim_provision_prerequisites
[[ -x "$HOME/mise-install/bin/nvim" && -x "$HOME/node-install/bin/node" ]] ||
  fail 'apply missed runtimes'
grep -qxF 'mise install node@lts' "$HOME/trace" || fail 'missing Node was not installed'
grep -qxF 'sudo apt-get install -y -- git sqlite3' "$HOME/trace" || fail 'sudo scope incorrect'
before="$(sha256sum "$HOME/trace")"
nvim_provision_prerequisites
[[ "$(sha256sum "$HOME/trace")" == "$before" ]] || fail 'second apply installed tools'
validate_nvim_prerequisites || fail 'installed prerequisites failed check'
[[ "$(sha256sum "$HOME/trace")" == "$before" ]] || fail 'check invoked installer'
pass

# Aqua archives may leave the executable one directory below the mise install root.
mkdir -p "$HOME/mise-install/nvim-linux-x86_64/bin"
mv "$HOME/mise-install/bin/nvim" "$HOME/mise-install/nvim-linux-x86_64/bin/nvim"
[[ "$(nvim_provision_binary)" == "$HOME/mise-install/nvim-linux-x86_64/bin/nvim" ]] ||
  fail 'nested mise Neovim executable was not resolved'
nvim_provision_prerequisites
validate_nvim_prerequisites || fail 'nested mise Neovim failed check'
[[ "$(sha256sum "$HOME/trace")" == "$before" ]] || fail 'nested runtime was reinstalled'
pass

# Installed mise Node must be reused even when not exposed on the shell PATH.
rm "$HOME/mise-install/nvim-linux-x86_64/bin/nvim"
if validate_nvim_prerequisites >/dev/null 2>&1; then fail 'missing Neovim passed check'; fi
[[ "$(sha256sum "$HOME/trace")" == "$before" ]] || fail 'check used mise exec/install'
nvim_provision_prerequisites
[[ "$(grep -c '^mise install node@lts$' "$HOME/trace")" == 1 ]] || fail 'installed mise Node was reinstalled'
before="$(sha256sum "$HOME/trace")"
pass

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/nvim" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/editor-trace"
exit "${EDITOR_EXIT:-0}"
SCRIPT
chmod +x "$HOME/.local/bin/nvim"
nvim_provision_editor
grep -qxF -- '--headless +lua require("config.dotfiles_provision").run()' "$HOME/editor-trace" ||
  fail 'editor provisioning entry point missing'
if ( export EDITOR_EXIT=9; nvim_provision_editor ) >/dev/null 2>&1; then fail 'editor error swallowed'; fi
pass

rm "$HOME/packages"
SELECTED_PROFILE=omarchy
if ( nvim_provision_prerequisites ) >"$HOME/arch-error" 2>&1; then fail 'Arch partial install allowed'; fi
grep -Fq 'sudo pacman -Syu' "$HOME/arch-error" || fail 'Arch full upgrade guidance absent'
[[ "$(sha256sum "$HOME/trace")" == "$before" ]] || fail 'Arch attempted install'
pass

# Omarchy also reuses/provisions user-owned Node without a native partial upgrade.
touch "$HOME/packages"
nvim_provision_prerequisites
validate_nvim_prerequisites || fail 'Omarchy did not accept installed mise Node'
[[ "$(sha256sum "$HOME/trace")" == "$before" ]] || fail 'Omarchy reinstalled existing Node'
rm "$HOME/node-install/bin/node"
nvim_provision_prerequisites
validate_nvim_prerequisites || fail 'Omarchy did not provision missing mise Node'
[[ "$(grep -c '^mise install node@lts$' "$HOME/trace")" == 2 ]] || fail 'Omarchy Node install missing'
pass
