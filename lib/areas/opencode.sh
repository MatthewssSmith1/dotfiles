# OpenCode configuration variants and exact canonical base bridge.

readonly OPENCODE_CANONICAL='.config/opencode/opencode.jsonc'
readonly OPENCODE_BASE_LEXICAL='base.jsonc'

register_opencode_area() {
  local package
  load_profile_closure opencode
  lean_begin_area opencode "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  lean_scan_packages
}

opencode_source() {
  printf '%s' "$DOTFILES_DIR/packages/common/opencode/.config/opencode/$1"
}

validate_opencode_payload() {
  local expected actual source
  [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == common/opencode ]] ||
    die 'OpenCode closure must contain only common/opencode'
  expected=$'.config/opencode/base.jsonc\n.config/opencode/profiles/personal.jsonc\n.config/opencode/profiles/work.jsonc\n.local/bin/dotfiles-opencode-profile\n.local/bin/opencode\n.local/bin/opencode-personal\n.local/bin/opencode-work\n.local/share/dotfiles/bin/opencode-launch'
  actual="$(printf '%s\n' "${LEAN_TARGET_PATHS[@]}" | LC_ALL=C sort)"
  [[ "$actual" == "$expected" ]] || die 'OpenCode package payload inventory is not exact'
  for source in "${LEAN_TARGET_SOURCES[@]}"; do
    if [[ "$source" == */.local/bin/* || "$source" == */.local/share/dotfiles/bin/* ]]; then
      [[ "$(stat -c %a -- "$source")" == 755 ]] || die "unexpected OpenCode executable mode: $source"
    else
      [[ "$(stat -c %a -- "$source")" == 644 ]] || die "unexpected OpenCode config mode: $source"
    fi
  done
  jq empty "$(opencode_source base.jsonc)" "$(opencode_source profiles/work.jsonc)" \
    "$(opencode_source profiles/personal.jsonc)" >/dev/null || die 'managed OpenCode config is invalid JSON'
}

opencode_canonical_is_exact() {
  local path="$HOME/$OPENCODE_CANONICAL"
  [[ -L "$path" && "$(readlink -- "$path")" == "$OPENCODE_BASE_LEXICAL" &&
    "$(resolve_link "$path")" == "$(opencode_source base.jsonc)" ]]
}

opencode_package_is_deployed() {
  local index
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    lean_link_is_exact "$index" && return 0
  done
  return 1
}

preflight_opencode_canonical() {
  local mode="$1" path="$HOME/$OPENCODE_CANONICAL"
  validate_home_parent_chain "$path"
  if [[ -e "$path" || -L "$path" ]]; then
    opencode_canonical_is_exact && return 0
    [[ "$mode" != remove ]] || ! opencode_package_is_deployed ||
      die "managed OpenCode configuration has a modified canonical base: $path"
    [[ "$mode" != remove ]] || return 0
    if [[ "$mode" == apply && -f "$path" && ! -L "$path" ]] &&
      cmp -s -- "$path" "$(opencode_source profiles/work.jsonc)"; then
      return 0
    fi
    die "unrelated OpenCode config conflicts with managed canonical base: $path"
  fi
  [[ "$mode" != check ]] || die "managed OpenCode canonical base is absent: $path"
}

preflight_opencode() {
  register_opencode_area
  validate_opencode_payload
  lean_preflight_area "$MODE"
  preflight_opencode_canonical "$MODE"
}

apply_opencode() {
  local path="$HOME/$OPENCODE_CANONICAL" adopted=false selector
  register_opencode_area
  validate_opencode_payload
  [[ ! -f "$path" || -L "$path" ]] || adopted=true
  lean_apply_area
  if [[ "$adopted" == true ]]; then
    cmp -s -- "$path" "$(opencode_source profiles/work.jsonc)" ||
      die 'OpenCode config changed after preflight; refusing adoption'
    rm -- "$path"
  fi
  if ! opencode_canonical_is_exact; then
    ln -sT -- "$OPENCODE_BASE_LEXICAL" "$path" 2>/dev/null ||
      die 'OpenCode canonical destination appeared concurrently; refusing to overwrite'
  fi
  if [[ "$adopted" == true ]]; then
    selector="$HOME/.config/dotfiles/local/opencode-profile"
    if [[ ! -e "$selector" && ! -L "$selector" ]]; then
      lean_ensure_directory "$(dirname -- "$selector")"
      printf 'work\n' > "$selector"
      chmod 600 "$selector"
    fi
  fi
  log "applied optional OpenCode area for profile '$SELECTED_PROFILE'"
}

remove_opencode() {
  register_opencode_area
  validate_opencode_payload
  lean_preflight_area remove
  preflight_opencode_canonical remove
  opencode_canonical_is_exact && rm -- "$HOME/$OPENCODE_CANONICAL"
  lean_remove_stow
  log 'removed exact managed OpenCode configuration links; preserved the host-local selector'
}
