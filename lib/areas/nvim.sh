# Personal Neovim area. Legacy default-editor objects are retired only after provisioning.
source "$(dirname -- "${BASH_SOURCE[0]}")/../nvim-provision.sh"

readonly NVIM_VERSION=0.12.4
readonly NVIM_SELECTOR="aqua:neovim/neovim@$NVIM_VERSION"
readonly NVIM_CONFIG_SOURCE='.config/nvim-matt'
readonly NVIM_NATIVE_LOADER='.config/nvim/plugin/dotfiles-personal.lua'
readonly NVIM_NATIVE_BEGIN='-- >>> dotfiles nvim >>>'
readonly NVIM_NATIVE_END='-- <<< dotfiles nvim <<<'
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
}

# The generic scanner inventories files, whereas Stow ignores this entire
# directory. Keep its inventory in sync locally without changing the engine.
nvim_scan_packages() {
  local index relative
  local paths=() sources=() lexical=()
  lean_scan_packages
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    relative="${LEAN_TARGET_PATHS[index]}"
    [[ "$relative" != "$NVIM_CONFIG_SOURCE/"* ]] || continue
    paths+=("$relative")
    sources+=("${LEAN_TARGET_SOURCES[index]}")
    lexical+=("${LEAN_TARGET_LEXICAL[index]}")
  done
  LEAN_TARGET_PATHS=("${paths[@]}")
  LEAN_TARGET_SOURCES=("${sources[@]}")
  LEAN_TARGET_LEXICAL=("${lexical[@]}")
}

validate_nvim_closure() {
  local expected=(.local/bin/nvim .local/share/applications/nvim-matt.desktop) config="$DOTFILES_DIR/packages/common/nvim/$NVIM_CONFIG_SOURCE"
  [[ -d "$config" && ! -L "$config" ]] || die 'personal Neovim config must be a repository directory'
  [[ -f "$config/init.lua" && ! -L "$config/init.lua" &&
    -f "$config/lazyvim.json" && ! -L "$config/lazyvim.json" &&
    -f "$config/lazy-lock.json" && ! -L "$config/lazy-lock.json" ]] || die 'personal Neovim config is incomplete'
  jq -e 'type == "object" and (.extras | type == "array")' "$config/lazyvim.json" >/dev/null ||
    die 'invalid personal Neovim extras configuration'
  jq -e 'type == "object" and length > 0 and all(.[];
    type == "object" and (.commit | type == "string" and test("^[0-9a-f]{40}$")))' \
    "$config/lazy-lock.json" >/dev/null || die 'invalid personal Neovim plugin lock'
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    [[ "${PACKAGES[*]}" == 'ubuntu/nvim common/nvim' ]] || die 'invalid Ubuntu Neovim closure'
    expected+=(.config/mise/conf.d/50-dotfiles-nvim-ubuntu.toml)
  else
    [[ "$SELECTED_PROFILE" == omarchy && "${PACKAGES[*]}" == 'common/nvim' ]] || die 'invalid Omarchy Neovim closure'
  fi
  nvim_scan_packages
  ((${#LEAN_TARGET_PATHS[@]} == ${#expected[@]})) ||
    die "personal Neovim package target inventory is not exact: ${LEAN_TARGET_PATHS[*]}"
  local target
  for target in "${expected[@]}"; do
    array_contains "$target" "${LEAN_TARGET_PATHS[@]}" || die "personal Neovim package missing target: $target"
  done
  [[ -x "$DOTFILES_DIR/packages/common/nvim/.local/bin/nvim" ]] || die 'Neovim launcher is not executable'
}

nvim_config_link_exact() {
  local path="$HOME/$NVIM_CONFIG_SOURCE" source="$DOTFILES_DIR/packages/common/nvim/$NVIM_CONFIG_SOURCE"
  local lexical
  lexical="$(realpath -m -s --relative-to="$(dirname -- "$path")" -- "$source")"
  [[ -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" &&
    "$(readlink -- "$path")" == "$lexical" && "$(resolve_link "$path")" == "$source" ]]
}

nvim_preflight_config_link() {
  local mode="$1" path="$HOME/$NVIM_CONFIG_SOURCE"
  validate_home_parent_chain "$path"
  if [[ -e "$path" || -L "$path" ]]; then
    nvim_config_link_exact || die "unrelated personal Neovim config at $path; move it aside before applying"
  elif [[ "$mode" == check ]]; then
    die "personal Neovim config link is absent: $path; run apply nvim"
  fi
}

nvim_apply_config_link() {
  local path="$HOME/$NVIM_CONFIG_SOURCE" source="$DOTFILES_DIR/packages/common/nvim/$NVIM_CONFIG_SOURCE"
  nvim_preflight_config_link apply
  nvim_config_link_exact && return 0
  lean_ensure_directory "$HOME/.config"
  ln -s -- "$(realpath -m -s --relative-to="$HOME/.config" -- "$source")" "$path" ||
    die "could not create personal Neovim config link: $path"
  nvim_config_link_exact || die "personal Neovim config link did not converge: $path"
}

nvim_remove_config_link() {
  local path="$HOME/$NVIM_CONFIG_SOURCE"
  nvim_preflight_config_link remove
  [[ -L "$path" ]] || return 0
  nvim_config_link_exact || die "personal Neovim config link changed: $path"
  rm -- "$path"
}

# Old links may be dangling after the old package was removed from the checkout.
# Compare the literal link destination, never the existence of its target.
nvim_legacy_links() {
  local relative="$1" path="$HOME/$relative" target root="$DOTFILES_DIR/packages" name layer suffix
  validate_home_parent_chain "$path"
  [[ -L "$path" ]] || return 1
  case "$relative" in
    .config/dotfiles/nvim/personal.lua|.config/dotfiles/nvim/ubuntu.lua|.local/share/dotfiles/bin/nvim-restore|\
    .config/nvim/.gitignore|.config/nvim/.neoconf.json|.config/nvim/LICENSE|.config/nvim/README.md|\
    .config/nvim/init.lua|.config/nvim/lazy-lock.json|.config/nvim/lazyvim.json|.config/nvim/stylua.toml|\
    .config/nvim/lua/config/autocmds.lua|.config/nvim/lua/config/keymaps.lua|\
    .config/nvim/lua/config/lazy.lua|.config/nvim/lua/config/options.lua|\
    .config/nvim/lua/config/remote_clipboard.lua|.config/nvim/lua/dotfiles_policy.lua|\
    .config/nvim/lua/plugins/all-themes.lua|.config/nvim/lua/plugins/disable-news-alert.lua|\
    .config/nvim/lua/plugins/dotfiles-runtime-policy.lua|.config/nvim/lua/plugins/example.lua|\
    .config/nvim/lua/plugins/neo-tree.lua|.config/nvim/lua/plugins/omarchy-theme-hotreload.lua|\
    .config/nvim/lua/plugins/snacks-animated-scrolling-off.lua|.config/nvim/lua/plugins/theme.lua|\
    .config/nvim/plugin/after/transparency.lua) ;;
    *) return 1 ;;
  esac
  case "$relative" in
    .config/dotfiles/nvim/personal.lua) layer=common ;;
    .config/nvim/lua/dotfiles_policy.lua|.config/nvim/lua/plugins/dotfiles-runtime-policy.lua|\
    .config/nvim/lua/plugins/neo-tree.lua|.config/nvim/lua/plugins/theme.lua|\
    .config/dotfiles/nvim/ubuntu.lua|.local/share/dotfiles/bin/nvim-restore) layer=ubuntu ;;
    *) layer=upstream ;;
  esac
  suffix="$relative"
  target="$(readlink -- "$path")"
  name="$(realpath -m -s -- "$target")"
  # Resolve relative lexical text against the link's directory without following it.
  [[ "$target" == /* ]] || name="$(realpath -m -s -- "$(dirname -- "$path")/$target")"
  [[ "$name" == "$root/$layer/nvim/$suffix" ]]
}

nvim_old_targets() {
  local path relative
  NVIM_OLD_LINKS=()
  for path in "$HOME/.config/dotfiles/nvim/personal.lua" "$HOME/.config/dotfiles/nvim/ubuntu.lua" \
    "$HOME/.local/share/dotfiles/bin/nvim-restore" "$HOME/.config/nvim"/* \
    "$HOME/.config/nvim"/.[!.]* "$HOME/.config/nvim"/..?* \
    "$HOME/.config/nvim/lua"/{config,plugins}/* "$HOME/.config/nvim/plugin/after"/*; do
    relative="${path#"$HOME"/}"
    validate_home_parent_chain "$path"
    [[ -L "$path" ]] || continue
    if nvim_legacy_links "$relative"; then NVIM_OLD_LINKS+=("$relative"); fi
  done
}

nvim_legacy_state() {
  local state="$HOME/.local/state/dotfiles/v2/nvim.json"
  NVIM_OLD_STATE=false
  [[ -e "$state" || -L "$state" ]] || return 0
  lean_validate_state_file "$state"
  [[ "$(jq -r .profile "$state")" == omarchy && "$SELECTED_PROFILE" == omarchy ]] || die 'unexpected Neovim ownership state'
  jq -e --arg path "$NVIM_NATIVE_LOADER" '.area == "nvim" and (.attachments | keys) == [$path] and
    .attachments[$path].id == "nvim-native-loader" and (.resources // {} | length) == 0' "$state" >/dev/null ||
    die 'unknown native Neovim attachment ownership'
  # Use the original block and the lean attachment inspection/removal primitives.
  lean_add_guarded_attachment nvim-native-loader "$NVIM_NATIVE_LOADER" \
    "$NVIM_NATIVE_BEGIN" "$NVIM_NATIVE_END" 'dotfiles nvim' "$NVIM_NATIVE_BLOCK" append 0644 true
  lean_preflight_attachments remove
  NVIM_OLD_STATE=true
  LEAN_ATTACHMENT_IDS=(); LEAN_ATTACHMENT_PATHS=(); LEAN_ATTACHMENT_BEGINS=(); LEAN_ATTACHMENT_ENDS=()
  LEAN_ATTACHMENT_TOKENS=(); LEAN_ATTACHMENT_BLOCKS=(); LEAN_ATTACHMENT_LEGACY_BLOCKS=()
  LEAN_ATTACHMENT_PLACEMENTS=(); LEAN_ATTACHMENT_MODES=(); LEAN_ATTACHMENT_REFRESHES=(); LEAN_ATTACHMENT_ANCHORS=()
}

validate_nvim_runtime() {
  local binary identity output version package_version
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    binary="${HOST_ROOT:-}/usr/bin/nvim"
    identity="$(omarchy_package_identity /usr/bin/nvim neovim 2>/dev/null || true)"
    [[ "$identity" =~ ^neovim\ ([0-9]+:)?([0-9][0-9A-Za-z._+~]*)-[0-9]+(\.[0-9]+)*$ ]] || {
      log_error "native /usr/bin/nvim must be owned by neovim: ${identity:-no package owner}"; return 1;
    }
    package_version="${BASH_REMATCH[2]}"
  else
    command -v mise >/dev/null 2>&1 && binary="$(nvim_provision_binary)" || {
      log_error "Ubuntu Neovim missing; run apply nvim to install $NVIM_SELECTOR"; return 1;
    }
  fi
  [[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] || { log_error "Neovim runtime missing: $binary"; return 1; }
  output="$("$binary" --version 2>/dev/null)" || return 1
  version="${output%%$'\n'*}"
  [[ "$version" =~ ^NVIM\ v([0-9][0-9A-Za-z._+~-]*)$ ]] || { log_error "invalid Neovim version: $version"; return 1; }
  version="${BASH_REMATCH[1]}"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$version" == "$package_version" ]] || { log_error 'native Neovim package/runtime mismatch'; return 1; }
  else
    [[ "$version" == "$NVIM_VERSION" ]] || { log_error "Ubuntu Neovim must be $NVIM_VERSION"; return 1; }
  fi
}

nvim_check_plugins() {
  local lock="$HOME/.config/nvim-matt/lazy-lock.json" name dir="$HOME/.local/share/nvim-matt/lazy"
  [[ -f "$lock" ]] || { log_error 'Neovim lockfile missing'; return 1; }
  while IFS= read -r name; do
    [[ -d "$dir/$name" && ! -L "$dir/$name" ]] || {
      log_error "Neovim plugin missing: $name; run apply nvim"; return 1;
    }
  done < <(jq -er 'keys[]' "$lock")
}

nvim_check_readiness() {
  local receipt="$HOME/.local/state/nvim-matt/dotfiles-ready.json"
  local data="$HOME/.local/share/nvim-matt" config="$HOME/.config/nvim-matt" file
  validate_home_parent_chain "$receipt"
  [[ -f "$receipt" && ! -L "$receipt" ]] && path_owned_by_euid "$receipt" || {
    log_error 'Neovim readiness receipt missing; run apply nvim'; return 1;
  }
  jq -e --arg data "$data" '
    type == "object" and (keys | sort) == ["extras_sha256","files","lock_sha256","version"] and
    .version == 1 and (.lock_sha256 | test("^[0-9a-f]{64}$")) and
    (.extras_sha256 | test("^[0-9a-f]{64}$")) and
    (.files | type == "array" and length > 0 and all(.[];
      type == "string" and startswith($data + "/") and
      (.[($data | length) + 1:] | split("/") | all(.[]; . != "" and . != "." and . != ".."))))
  ' "$receipt" >/dev/null 2>&1 || { log_error 'invalid Neovim readiness receipt; run apply nvim'; return 1; }
  [[ "$(jq -r .lock_sha256 "$receipt")" == "$(sha256_file "$config/lazy-lock.json")" &&
    "$(jq -r .extras_sha256 "$receipt")" == "$(sha256_file "$config/lazyvim.json")" ]] || {
    log_error 'Neovim configuration changed since provisioning; run apply nvim'; return 1;
  }
  while IFS= read -r file; do
    validate_home_parent_chain "$file"
    [[ -f "$file" && ! -L "$file" ]] || {
      log_error "Neovim readiness artifact missing: $file; run apply nvim"; return 1;
    }
  done < <(jq -r '.files[]' "$receipt")
}

preflight_nvim() {
  register_nvim_area
  validate_nvim_closure
  nvim_old_targets
  nvim_legacy_state
  nvim_preflight_config_link "$MODE"
  lean_refuse_v1_state
  lean_validate_all_state
  if [[ "$MODE" == apply ]]; then
    lean_preflight_links apply
    lean_run_stow_preflight apply
  else
    # A legacy attachment remains valid during migration, but a check requires
    # the new personal deployment and a fully retired old attachment.
    [[ "$NVIM_OLD_STATE" != true || "$MODE" == remove ]] || die 'legacy Neovim loader still attached; run apply nvim'
    lean_preflight_links "$MODE"
    lean_run_stow_preflight "$MODE"
    if [[ "$MODE" == check ]]; then
      validate_nvim_runtime && validate_nvim_prerequisites || return 1
      nvim_check_plugins || return 1
      nvim_check_readiness || return 1
    fi
  fi
}

nvim_retire_legacy() {
  local relative path index=0
  for relative in "${NVIM_OLD_LINKS[@]}"; do
    path="$HOME/$relative"
    nvim_legacy_links "$relative" || die "old Neovim link changed: $path"
    rm -- "$path"
  done
  [[ "$NVIM_OLD_STATE" == true ]] || return 0
  lean_add_guarded_attachment nvim-native-loader "$NVIM_NATIVE_LOADER" \
    "$NVIM_NATIVE_BEGIN" "$NVIM_NATIVE_END" 'dotfiles nvim' "$NVIM_NATIVE_BLOCK" append 0644 true
  lean_preflight_attachments remove
  lean_remove_attachment "$index"
  lean_validate_state_file "$LEAN_STATE"
  rm -- "$LEAN_STATE"
}

apply_nvim() {
  preflight_nvim
  nvim_provision_prerequisites
  # This package-only area needs only Stow. The legacy attachment state stays
  # in place until the newly provisioned editor is usable.
  lean_preflight_links apply
  lean_run_stow_preflight apply
  lean_apply_stow
  nvim_apply_config_link
  nvim_provision_editor
  nvim_retire_legacy
  log_success 'personal Neovim deployed and provisioned'
}

remove_nvim() {
  MODE=remove preflight_nvim
  lean_remove_stow
  nvim_remove_config_link
  nvim_retire_legacy
  log_success 'removed personal Neovim links; retained editor data and installed tools'
}
