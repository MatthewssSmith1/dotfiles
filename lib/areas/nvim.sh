# Neovim area: native package validation/personal loader or Ubuntu package closure.

readonly NVIM_VERSION='0.12.4'
readonly NVIM_SELECTOR="aqua:neovim/neovim@$NVIM_VERSION"
readonly NVIM_NATIVE_PACKAGES='neovim 0.12.4-1|neovim 0.12.5-1'
readonly NVIM_NATIVE_BASELINE_PACKAGE='omarchy-nvim 2026.8.13-1'
readonly NVIM_NATIVE_CONFIG='.config/nvim/init.lua'
readonly NVIM_NATIVE_LOADER='.config/nvim/plugin/dotfiles-personal.lua'
readonly NVIM_NATIVE_BEGIN='-- >>> dotfiles nvim >>>'
readonly NVIM_NATIVE_END='-- <<< dotfiles nvim <<<'
readonly NVIM_NATIVE_TOKEN='dotfiles nvim'
readonly NVIM_NATIVE_BLOCK="$NVIM_NATIVE_BEGIN
local personal = vim.fn.expand('~/.config/dotfiles/nvim/personal.lua')
if (vim.uv or vim.loop).fs_stat(personal) then
  dofile(personal)
end
$NVIM_NATIVE_END"

register_nvim_area() {
  local package
  load_profile_closure nvim
  lean_begin_area nvim "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    lean_add_guarded_attachment nvim-native-loader "$NVIM_NATIVE_LOADER" \
      "$NVIM_NATIVE_BEGIN" "$NVIM_NATIVE_END" "$NVIM_NATIVE_TOKEN" "$NVIM_NATIVE_BLOCK" append 0644 true
  fi
}

validate_nvim_runtime() {
  local binary output identity version version_line expected package_version baseline_identity
  binary="${DOTFILES_TEST_NVIM_BIN:-$(type -P nvim 2>/dev/null || true)}"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    expected="${HOST_ROOT:-}/usr/bin/nvim"
    [[ "$binary" == "$expected" ]] ||
      die "native Neovim must resolve to package-owned /usr/bin/nvim, not '${binary:-missing}'; refresh or reinstall Neovim, then rerun validation"
    identity="$(omarchy_package_identity /usr/bin/nvim neovim 2>/dev/null || true)"
    [[ "$identity" =~ ^neovim[[:space:]]([0-9]+:)?([0-9][0-9A-Za-z._+~]*)-([0-9]+(\.[0-9]+)*)$ ]] ||
      die "native /usr/bin/nvim must be owned by neovim with valid version metadata, found '${identity:-no package owner}'; reinstall Neovim, then rerun validation"
    package_version="${BASH_REMATCH[2]}"
    [[ "|$NVIM_NATIVE_PACKAGES|" == *"|$identity|"* ]] ||
      log_warning "native Neovim package version is unreviewed: installed=$identity recorded=$NVIM_NATIVE_PACKAGES"
    baseline_identity="$(omarchy_package_identity /usr/share/omarchy-nvim omarchy-nvim 2>/dev/null || true)"
    [[ "$baseline_identity" =~ ^omarchy-nvim[[:space:]]([0-9]+:)?([0-9][0-9A-Za-z._+~]*)-([0-9]+(\.[0-9]+)*)$ ]] ||
      die "native Neovim baseline must be owned by omarchy-nvim with valid version metadata, found '${baseline_identity:-no package owner}'; reinstall omarchy-nvim, then rerun validation"
    [[ "$baseline_identity" == "$NVIM_NATIVE_BASELINE_PACKAGE" ]] ||
      log_warning "native omarchy-nvim package version is unreviewed: installed=$baseline_identity recorded=$NVIM_NATIVE_BASELINE_PACKAGE"
  elif [[ -z "$binary" ]]; then
    log_error "Neovim is absent; install it manually with: mise install $NVIM_SELECTOR"
    return 1
  fi
  [[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] ||
    die "selected Neovim runtime is not a directly executable regular file: ${binary:-missing}"
  output="$($binary --version 2>/dev/null || true)"
  version_line="${output%%$'\n'*}"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$version_line" =~ ^NVIM\ v([0-9][0-9A-Za-z._+~-]*)$ ]] ||
      die "selected Neovim returned an invalid version: ${output:-missing}"
    version="${BASH_REMATCH[1]}"
    [[ "$version" == "$package_version" ]] ||
      die "native Neovim runtime version $version does not match package version $package_version"
  else
    [[ "$version_line" =~ ^NVIM\ v([0-9]+\.[0-9]+\.[0-9]+)$ ]] ||
      die "selected Neovim returned an invalid version: ${output:-missing}"
    version="${BASH_REMATCH[1]}"
    [[ "$version" == "$NVIM_VERSION" ]] ||
      die "Ubuntu Neovim must report NVIM v$NVIM_VERSION; install it with: mise install $NVIM_SELECTOR"
  fi
}

validate_native_nvim_attachment_presence() {
  local state="$HOME/.local/state/dotfiles/v2/nvim.json"
  [[ "$MODE" != check ]] || {
    [[ -f "$state" && -e "$HOME/$NVIM_NATIVE_LOADER" &&
      -e "$HOME/.config/dotfiles/nvim/personal.lua" ]] ||
      die "native Neovim personal layer ownership, loader, or source is missing; repair it with: ./dotfiles.sh apply nvim"
  }
}

validate_nvim_closure() {
  local expected index relative source selector
  local -a expected_targets=(
    .config/dotfiles/nvim/personal.lua
  )
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'common/nvim' ]] ||
      die 'native Neovim closure must contain only common/nvim'
  else
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'upstream/nvim ubuntu/nvim common/nvim' ]] ||
      die 'Ubuntu Neovim closure must contain upstream/nvim, ubuntu/nvim, and common/nvim'
    expected_targets+=(
      .config/dotfiles/nvim/ubuntu.lua
      .config/mise/conf.d/50-dotfiles-nvim-ubuntu.toml
      .config/nvim/.gitignore .config/nvim/.neoconf.json .config/nvim/LICENSE .config/nvim/README.md
      .config/nvim/init.lua .config/nvim/lazy-lock.json .config/nvim/lazyvim.json
      .config/nvim/lua/config/autocmds.lua .config/nvim/lua/config/keymaps.lua
      .config/nvim/lua/config/lazy.lua .config/nvim/lua/config/options.lua
      .config/nvim/lua/config/remote_clipboard.lua .config/nvim/lua/dotfiles_policy.lua
      .config/nvim/lua/plugins/all-themes.lua .config/nvim/lua/plugins/disable-news-alert.lua
      .config/nvim/lua/plugins/dotfiles-runtime-policy.lua .config/nvim/lua/plugins/example.lua
      .config/nvim/lua/plugins/neo-tree.lua .config/nvim/lua/plugins/omarchy-theme-hotreload.lua
      .config/nvim/lua/plugins/snacks-animated-scrolling-off.lua .config/nvim/lua/plugins/theme.lua
      .config/nvim/plugin/after/transparency.lua .config/nvim/stylua.toml
      .local/share/dotfiles/bin/nvim-restore
    )
    selector="$DOTFILES_DIR/packages/ubuntu/nvim/.config/mise/conf.d/50-dotfiles-nvim-ubuntu.toml"
    grep -qxF '"aqua:neovim/neovim" = "0.12.4"' "$selector" ||
      die 'Ubuntu Neovim mise selector is not the accepted 0.12.4 release'
    jq -e 'type == "object" and length > 0 and (."lazy.nvim".commit | test("^[0-9a-f]{40}$"))' \
      "$DOTFILES_DIR/packages/upstream/nvim/.config/nvim/lazy-lock.json" >/dev/null ||
      die 'invalid accepted Neovim lockfile'
    if [[ "$MODE" != remove ]]; then
      "$DOTFILES_DIR/scripts/upstream" verify >/dev/null || die 'accepted Neovim snapshot verification failed'
    fi
  fi
  lean_scan_expected_targets 'Neovim package' "${expected_targets[@]}"
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    relative="${LEAN_TARGET_PATHS[index]}"; source="${LEAN_TARGET_SOURCES[index]}"
    if [[ "$relative" == .local/share/dotfiles/bin/* ]]; then
      [[ "$(stat -c %a -- "$source")" == 755 ]] || die "Neovim helper is not executable: $relative"
    else
      [[ "$(stat -c %a -- "$source")" == 644 ]] || die "unexpected Neovim payload mode: $relative"
    fi
  done
}

validate_native_nvim_baseline() {
  local path="$HOME/$NVIM_NATIVE_CONFIG"
  validate_home_parent_chain "$path"
  [[ -f "$path" && ! -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] ||
    die "native package-owned Neovim baseline is missing or unsafe: $path"
}

preflight_nvim() {
  register_nvim_area
  validate_nvim_closure
  if [[ "$MODE" == remove ]]; then
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      validate_nvim_runtime
      validate_native_nvim_baseline
    fi
    lean_preflight_area remove
    return
  fi
  validate_nvim_runtime
  [[ "$SELECTED_PROFILE" != omarchy ]] || validate_native_nvim_baseline
  [[ "$SELECTED_PROFILE" != omarchy ]] || validate_native_nvim_attachment_presence
  lean_preflight_area "$MODE"
}

apply_nvim() {
  preflight_nvim
  lean_apply_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log_success 'retained the package-owned native Neovim baseline and applied only the personal layer/loader'
  else
    log_success "applied the Ubuntu Neovim baseline, adapter, personal layer, restore helper, and selector; install the runtime manually with: mise install $NVIM_SELECTOR"
  fi
}

remove_nvim() {
  register_nvim_area
  validate_nvim_closure
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    validate_nvim_runtime
    validate_native_nvim_baseline
  fi
  lean_remove_area
  log_success 'removed only exact managed Neovim links and personal loader; retained all runtime data'
}
