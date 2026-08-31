# OpenCode profile overlays and named launchers.

register_opencode_area() {
  local package
  load_profile_closure opencode
  lean_begin_area opencode "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  lean_scan_packages
}

opencode_source() {
  printf '%s' "$DOTFILES_DIR/packages/common/opencode/.config/dotfiles/opencode/$1"
}

opencode_json() {
  jq -eRsc '
    gsub("(?m)^\\s*//[^\\n]*(\\n|$)"; "") |
    gsub(",(?<close>\\s*[}\\]])"; "\(.close)") |
    fromjson
  ' "$1"
}

opencode_legacy_link_is_exact() {
  local target="$1" source="$2" path
  path="$HOME/$target"
  [[ -L "$path" && "$(resolve_link "$path")" == "$DOTFILES_DIR/packages/common/opencode/$source" ]]
}

opencode_legacy_canonical_is_exact() {
  local path="$HOME/.config/opencode/opencode.jsonc"
  [[ -L "$path" && "$(readlink -- "$path")" == base.jsonc ]] &&
    opencode_legacy_link_is_exact .config/opencode/base.jsonc .config/opencode/base.jsonc
}

opencode_legacy_links_present() {
  opencode_legacy_link_is_exact .config/opencode/base.jsonc .config/opencode/base.jsonc ||
    opencode_legacy_link_is_exact .config/opencode/dotfiles-tui.jsonc .config/opencode/dotfiles-tui.jsonc ||
    opencode_legacy_link_is_exact .config/opencode/profiles/personal.jsonc .config/opencode/profiles/personal.jsonc ||
    opencode_legacy_link_is_exact .config/opencode/profiles/work.jsonc .config/opencode/profiles/work.jsonc ||
    opencode_legacy_link_is_exact .local/bin/dotfiles-opencode-profile .local/bin/dotfiles-opencode-profile ||
    opencode_legacy_link_is_exact .local/bin/opencode .local/bin/opencode ||
    opencode_legacy_canonical_is_exact
}

remove_opencode_legacy_links() {
  local target source target_source
  local -a legacy=(
    '.config/opencode/base.jsonc .config/opencode/base.jsonc'
    '.config/opencode/dotfiles-tui.jsonc .config/opencode/dotfiles-tui.jsonc'
    '.config/opencode/profiles/personal.jsonc .config/opencode/profiles/personal.jsonc'
    '.config/opencode/profiles/work.jsonc .config/opencode/profiles/work.jsonc'
    '.local/bin/dotfiles-opencode-profile .local/bin/dotfiles-opencode-profile'
    '.local/bin/opencode .local/bin/opencode'
  )
  opencode_legacy_canonical_is_exact && rm -- "$HOME/.config/opencode/opencode.jsonc"
  for target_source in "${legacy[@]}"; do
    read -r target source <<< "$target_source"
    opencode_legacy_link_is_exact "$target" "$source" && rm -- "$HOME/$target"
  done
  return 0
}

validate_opencode_payload() {
  local expected actual source
  [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == common/opencode ]] ||
    die 'OpenCode closure must contain only common/opencode'
  expected=$'.config/dotfiles/opencode/personal.jsonc\n.config/dotfiles/opencode/tui.jsonc\n.config/dotfiles/opencode/work.jsonc\n.local/bin/opencode-personal\n.local/bin/opencode-work\n.local/share/dotfiles/bin/opencode-launch'
  actual="$(printf '%s\n' "${LEAN_TARGET_PATHS[@]}" | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] || die 'OpenCode package payload inventory is not exact'
  for source in "${LEAN_TARGET_SOURCES[@]}"; do
    if [[ "$source" == */.local/bin/* || "$source" == */.local/share/dotfiles/bin/* ]]; then
      [[ "$(stat -c %a -- "$source")" == 755 ]] || die "unexpected OpenCode executable mode: $source"
    else
      [[ "$(stat -c %a -- "$source")" == 644 ]] || die "unexpected OpenCode config mode: $source"
    fi
  done
  jq empty "$(opencode_source personal.jsonc)" "$(opencode_source tui.jsonc)" \
    "$(opencode_source work.jsonc)" >/dev/null || die 'managed OpenCode config is invalid JSON'
}

validate_opencode_global_configs() {
  local name path parsed
  for name in config.json opencode.json opencode.jsonc; do
    path="$HOME/.config/opencode/$name"
    validate_home_parent_chain "$path"
    [[ -e "$path" || -L "$path" ]] || continue
    [[ "$name" != opencode.jsonc ]] || ! opencode_legacy_canonical_is_exact || continue
    [[ -f "$path" && ! -L "$path" && -r "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] ||
      die "global OpenCode config is not a readable EUID-owned regular file: $path"
    file_contains_nul "$path" && die "global OpenCode config contains NUL bytes: $path"
    parsed="$(opencode_json "$path")" || die "global OpenCode config is invalid JSON/JSONC: $path"
    [[ "$(jq -r type <<< "$parsed")" == object ]] || die "global OpenCode config is not an object: $path"
    if jq -e 'has("plugin") or has("provider")' <<< "$parsed" >/dev/null; then
      die "global OpenCode config declares plugin or provider settings: $path"
    fi
  done
}

preflight_opencode() {
  register_opencode_area
  validate_opencode_payload
  [[ "$MODE" != check ]] || ! opencode_legacy_links_present ||
    die 'legacy managed OpenCode links remain; run dotfiles.sh apply opencode to migrate them'
  [[ "$MODE" == remove ]] || validate_opencode_global_configs
  lean_preflight_area "$MODE"
}

apply_opencode() {
  register_opencode_area
  validate_opencode_payload
  validate_opencode_global_configs
  lean_preflight_area apply
  remove_opencode_legacy_links
  validate_opencode_global_configs
  lean_apply_area
  log "applied optional OpenCode area for profile '$SELECTED_PROFILE'"
}

remove_opencode() {
  register_opencode_area
  validate_opencode_payload
  lean_preflight_area remove
  remove_opencode_legacy_links
  lean_remove_stow
  log 'removed exact managed OpenCode profile and launcher links'
}
