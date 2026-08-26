# Mise configuration area converted to the lean package-only lifecycle.

readonly TOOLS_PNPM_SELECTOR='aqua:pnpm/pnpm@11.13.1'
readonly TOOLS_WORKTRUNK_SELECTOR='aqua:max-sixty/worktrunk@0.68.0'

register_tools_area() {
  local package
  load_profile_closure tools
  lean_begin_area tools "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
}

validate_tools_fragments() {
  local common="$DOTFILES_DIR/packages/common/tools/.config/mise/conf.d/20-dotfiles-tools.toml"
  local ubuntu="$DOTFILES_DIR/packages/ubuntu/tools/.config/mise/conf.d/30-dotfiles-tools-ubuntu.toml"
  [[ -f "$common" && -f "$ubuntu" ]] || die 'managed mise fragments are missing'
  grep -qxF '"aqua:pnpm/pnpm" = "11.13.1"' "$common" || die 'pnpm selector is not the accepted 11.13.1 release'
  grep -qxF '"aqua:max-sixty/worktrunk" = "0.68.0"' "$common" || die 'Worktrunk selector is not the accepted 0.68.0 release'
  grep -qxF 'not_found_auto_install = false' "$common" || die 'mise automatic installation is not disabled'
  grep -qxF 'idiomatic_version_file_enable_tools = []' "$common" || die 'mise idiomatic version files are not disabled'
  ! grep -Eq '^[[:space:]]*locked[[:space:]]*=' "$common" "$ubuntu" || die 'managed mise configuration must not enable locked mode'
  ! grep -Eq '^[[:space:]]*node[[:space:]]*=' "$common" || die 'common tools must not select Node'
  grep -qxF 'node = "lts"' "$ubuntu" || die 'Ubuntu tools must select the Node LTS fallback'
}

tools_missing_guidance() {
  local missing=false
  if ! command_capability_exists mise; then
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      log 'error: mise is absent; install the native owner manually with: omarchy pkg add mise-bin'
    else
      log 'error: mise is absent; install mise manually, then rerun this check'
    fi
    missing=true
  fi
  if [[ "$SELECTED_PROFILE" == ubuntu ]] && ! command_capability_exists node; then
    log 'error: Node is absent; install the selected fallback manually with: mise install node@lts'
    missing=true
  fi
  if ! command_capability_exists pnpm; then
    log "error: pnpm is absent; install it manually with: mise install $TOOLS_PNPM_SELECTOR"
    missing=true
  fi
  if ! command_capability_exists wt; then
    log "error: Worktrunk is absent; install it manually with: mise install $TOOLS_WORKTRUNK_SELECTOR"
    missing=true
  fi
  [[ "$missing" == false ]]
}

validate_selected_tool_versions() {
  local actual
  actual="$(pnpm --version 2>/dev/null || true)"
  [[ "$actual" == 11.13.1 ]] || die "pnpm must resolve to 11.13.1, found '${actual:-missing}'"
  actual="$(wt --version 2>/dev/null || true)"
  [[ "$actual" == *0.68.0* ]] || die "Worktrunk must resolve to 0.68.0, found '${actual:-missing}'"
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    node --version >/dev/null 2>&1 || die 'Ubuntu Node LTS fallback is not executable'
  fi
}

preflight_tools() {
  validate_tools_fragments
  if [[ "$MODE" == check ]]; then tools_missing_guidance || return 1; fi
  register_tools_area
  lean_preflight_area "$MODE"
  if [[ "$MODE" == check ]]; then
    validate_selected_tool_versions
  fi
}

apply_tools() {
  register_tools_area
  lean_apply_area
  log "applied tools area for profile '$SELECTED_PROFILE'; install selected tools manually with mise"
}

remove_tools() {
  register_tools_area
  lean_remove_area
  log 'removed exact managed mise configuration links'
}
