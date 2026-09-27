# Sourced after lib/areas/nvim.sh. Apply only; validation is local and read-only.
# Arch intentionally refuses missing packages: pacman -S without a synchronized
# full upgrade can be a partial upgrade. Run sudo pacman -Syu separately.

nvim_provision_command() {
  command -v "$1" >/dev/null 2>&1
}

nvim_provision_missing_packages() {
  local package
  NVIM_MISSING_PACKAGES=()
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    for package in git curl unzip build-essential python3 python3-venv sqlite3 ripgrep fd-find; do
      dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' ||
        NVIM_MISSING_PACKAGES+=("$package")
    done
  else
    for package in neovim git curl unzip base-devel python sqlite ripgrep fd; do
      pacman -Qq "$package" >/dev/null 2>&1 || NVIM_MISSING_PACKAGES+=("$package")
    done
  fi
}

nvim_provision_mise() {
  # Explicitly resolve the selector, independent of interactive shell activation.
  mise where -C "$HOME" "$NVIM_SELECTOR" 2>/dev/null
}

nvim_provision_node_pair() {
  local directory="${1:-}"
  if [[ -n "$directory" ]]; then
    [[ -x "$directory/bin/node" && -f "$directory/bin/npm" ]] || return 1
    PATH="$directory/bin:$PATH" "$directory/bin/node" -e \
      'process.exit(Number(process.versions.node.split(".")[0]) < 20 ? 1 : 0)' >/dev/null 2>&1 &&
      PATH="$directory/bin:$PATH" "$directory/bin/npm" --version >/dev/null 2>&1
  else
    nvim_provision_command node && nvim_provision_command npm &&
      node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 20 ? 1 : 0)' >/dev/null 2>&1 &&
      npm --version >/dev/null 2>&1
  fi
}

nvim_provision_mise_node() {
  mise where -C "$HOME" node@lts 2>/dev/null
}

nvim_provision_prerequisites() {
  local install_dir node_dir
  [[ "$EUID" != 0 ]] || die 'Neovim provisioning must run as the regular user'
  case "$SELECTED_PROFILE" in ubuntu|omarchy) ;; *) die "unsupported Neovim profile: $SELECTED_PROFILE" ;; esac
  nvim_provision_missing_packages
  if ((${#NVIM_MISSING_PACKAGES[@]})); then
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      die "missing Arch Neovim prerequisites: ${NVIM_MISSING_PACKAGES[*]}; run a full system upgrade with: sudo pacman -Syu ${NVIM_MISSING_PACKAGES[*]}"
    fi
    nvim_provision_command sudo || die "sudo is needed for Ubuntu Neovim packages: ${NVIM_MISSING_PACKAGES[*]}"
    log "installing missing Ubuntu Neovim packages: ${NVIM_MISSING_PACKAGES[*]}"
    sudo apt-get install -y -- "${NVIM_MISSING_PACKAGES[@]}" ||
      die "Ubuntu package installation failed: ${NVIM_MISSING_PACKAGES[*]}; update apt indexes manually if needed"
  fi
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    nvim_provision_command mise || die 'mise is missing; install mise for the Ubuntu Neovim runtime'
    if ! install_dir="$(nvim_provision_mise)" || [[ ! -x "$install_dir/bin/nvim" ]]; then
      mise install "$NVIM_SELECTOR" || die "Neovim runtime installation failed: $NVIM_SELECTOR"
    fi
    install_dir="$(nvim_provision_mise)" && [[ -x "$install_dir/bin/nvim" ]] ||
      die "mise did not provide an executable Neovim: $NVIM_SELECTOR"
  fi
  # Reuse a functional host pair or installed mise fallback on either host.
  if ! nvim_provision_node_pair; then
    nvim_provision_command mise || die 'mise is missing; install mise or provide compatible Node (>=20) and npm'
    if ! node_dir="$(nvim_provision_mise_node)" || ! nvim_provision_node_pair "$node_dir"; then
      mise install node@lts || die 'Node/npm installation failed: node@lts'
    fi
    node_dir="$(nvim_provision_mise_node)" && nvim_provision_node_pair "$node_dir" ||
      die 'mise node@lts does not provide compatible Node (>=20) and npm'
  fi
}

validate_nvim_prerequisites() {
  local missing=0 install_dir node_dir
  case "$SELECTED_PROFILE" in ubuntu|omarchy) ;; *) log_error "unsupported Neovim profile: $SELECTED_PROFILE"; return 1 ;; esac
  nvim_provision_missing_packages
  if ((${#NVIM_MISSING_PACKAGES[@]})); then
    log_error "missing Neovim packages: ${NVIM_MISSING_PACKAGES[*]}"
    missing=1
  fi
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    if ! nvim_provision_command mise || ! install_dir="$(nvim_provision_mise)" || [[ ! -x "$install_dir/bin/nvim" ]]; then
      log_error "Neovim runtime missing; run apply nvim to install $NVIM_SELECTOR"
      missing=1
    fi
  fi
  if ! nvim_provision_node_pair; then
    # `mise where` only inspects installed tools; never use `mise exec` in check.
    if ! nvim_provision_command mise ||
      ! node_dir="$(nvim_provision_mise_node)" || ! nvim_provision_node_pair "$node_dir"; then
      log_error 'compatible Node (>=20) and npm missing; run apply nvim'
      missing=1
    fi
  fi
  return "$missing"
}

nvim_provision_editor() {
  local launcher="$HOME/.local/bin/nvim"
  [[ -x "$launcher" ]] || die "personal Neovim launcher is missing: $launcher"
  DOTFILES_NVIM_PROVISIONING=1 "$launcher" --headless '+lua require("config.dotfiles_provision").run()' ||
    die 'Neovim plugin/Mason/Treesitter provisioning failed; rerun apply nvim after resolving the editor error'
}
