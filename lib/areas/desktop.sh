# Native Omarchy desktop overrides; Ubuntu intentionally validates only.

readonly DESKTOP_INPUT='.config/hypr/input.lua'
readonly DESKTOP_INPUT_FRAGMENT='.config/dotfiles/omarchy/hypr/input.lua'
readonly DESKTOP_XCOMPOSE='.XCompose'
readonly DESKTOP_XCOMPOSE_ALIASES='.config/dotfiles/omarchy/XCompose'
readonly DESKTOP_SHELL='.config/omarchy/shell.json'
readonly DESKTOP_MENU_EXTENSION='.config/omarchy/extensions/omarchy-menu.jsonc'
readonly DESKTOP_THEME_SWITCHER='.local/bin/dotfiles-omarchy-theme-switcher'
readonly DESKTOP_INPUT_BEGIN='-- >>> dotfiles desktop input >>>'
readonly DESKTOP_INPUT_END='-- <<< dotfiles desktop input <<<'
readonly DESKTOP_INPUT_TOKEN='dotfiles desktop input'
readonly DESKTOP_INPUT_BLOCK="$DESKTOP_INPUT_BEGIN
local home = os.getenv(\"HOME\")
if home and home ~= \"\" then
  local fragment = home .. \"/$DESKTOP_INPUT_FRAGMENT\"
  local handle = io.open(fragment, \"r\")
  if handle then
    handle:close()
    dofile(fragment)
  end
end
$DESKTOP_INPUT_END"
readonly DESKTOP_XCOMPOSE_BEGIN='# >>> dotfiles desktop xcompose >>>'
readonly DESKTOP_XCOMPOSE_END='# <<< dotfiles desktop xcompose <<<'
readonly DESKTOP_XCOMPOSE_TOKEN='dotfiles desktop xcompose'
readonly DESKTOP_XCOMPOSE_BLOCK="$DESKTOP_XCOMPOSE_BEGIN
include \"%H/.config/dotfiles/omarchy/XCompose\"
$DESKTOP_XCOMPOSE_END"

register_desktop_area() {
  local package
  load_profile_closure desktop
  lean_begin_area desktop "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    lean_add_guarded_attachment desktop-input-v1 "$DESKTOP_INPUT" \
      "$DESKTOP_INPUT_BEGIN" "$DESKTOP_INPUT_END" "$DESKTOP_INPUT_TOKEN" \
      "$DESKTOP_INPUT_BLOCK" append 0644 true
    lean_add_guarded_attachment desktop-xcompose-v1 "$DESKTOP_XCOMPOSE" \
      "$DESKTOP_XCOMPOSE_BEGIN" "$DESKTOP_XCOMPOSE_END" "$DESKTOP_XCOMPOSE_TOKEN" \
      "$DESKTOP_XCOMPOSE_BLOCK" append 0644 true
    lean_add_json_scalar_fields desktop-shell-idle-v1 "$DESKTOP_SHELL" validate_desktop_shell_json \
      /idle/screensaver integer 600 /idle/lock integer 900
  fi
}

validate_desktop_xcompose_aliases() {
  local path="$DOTFILES_DIR/packages/omarchy/desktop/$DESKTOP_XCOMPOSE_ALIASES"
  local expected='<Multi_key> <space> <a> : "AGENTS.md"
<Multi_key> <p> <b> : "Continue discussing with me briefly."
<Multi_key> <p> <d> : "Continue discussing with me, focussing on points we have yet to agree on."
<Multi_key> <p> <t> : "What do you think/recommend? Discuss with me."'
  [[ -f "$path" && ! -L "$path" && "$(< "$path")" == "$expected" ]] ||
    die 'desktop XCompose aliases are not the accepted exact bindings'
}

validate_desktop_fragment() {
  local path="$DOTFILES_DIR/packages/omarchy/desktop/$DESKTOP_INPUT_FRAGMENT"
  local expected='hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
    },
  },
})'
  [[ -f "$path" && ! -L "$path" && "$(< "$path")" == "$expected" ]] ||
    die 'desktop input fragment is not the accepted minimal natural-scroll override'
}

validate_desktop_shell_json() {
  jq -e '
    type == "object" and .version == 1 and
    (.idle | type == "object") and
    (.idle.screensaver | type == "number" and floor == .) and
    (.idle.lock | type == "number" and floor == .)
  ' "$1" >/dev/null
}

validate_desktop_stock_input() {
  local stock="${HOST_ROOT:-}/usr/share/omarchy/config/hypr/input.lua"
  local installed_identity stock_identity installed_version stock_version
  [[ -f "$stock" && ! -L "$stock" ]] || die "Omarchy stock input baseline is missing or unsafe: $stock"
  installed_identity="$(omarchy_package_identity /usr/share/omarchy/version 2>/dev/null || true)"
  stock_identity="$(omarchy_package_identity /usr/share/omarchy/config/hypr/input.lua omarchy-settings 2>/dev/null || true)"
  [[ -n "$installed_identity" ]] || die 'Omarchy core does not have an authoritative package identity'
  [[ -n "$stock_identity" ]] || die 'Omarchy stock input baseline is not owned by omarchy-settings'
  installed_version="${installed_identity#omarchy }"
  stock_version="${stock_identity#omarchy-settings }"
  [[ "$stock_version" == "$installed_version" ]] ||
    die 'Omarchy settings package version does not exactly match authoritative Omarchy'
}

validate_desktop_theme_filter() {
  local package="$DOTFILES_DIR/packages/omarchy/desktop" menu selector hidden
  menu="$package/$DESKTOP_MENU_EXTENSION"
  selector="$package/$DESKTOP_THEME_SWITCHER"
  [[ -f "$menu" && ! -L "$menu" ]] || die 'desktop menu extension is missing or unsafe'
  [[ -f "$selector" && ! -L "$selector" && -x "$selector" && "$(stat -c %a -- "$selector")" == 755 ]] ||
    die 'desktop theme selector is not an accepted executable payload'
  bash -n "$selector" || die 'desktop theme selector has invalid Bash syntax'
  mapfile -t hidden < <(awk '/^readonly -a HIDDEN_THEMES=\($/{inside=1; next} inside && /^\)/{exit} inside {sub(/^[[:space:]]+/, ""); print}' "$selector")
  [[ "${hidden[*]}" == 'ethereal flexoki-light hackerman last-horizon lumon lupine miasma rose-pine vantablack white' ]] ||
    die 'desktop theme selector denylist is not exact'
  jq -e '
    keys == ["style.theme"] and
    .["style.theme"].icon == "󰸌" and
    .["style.theme"].label == "Theme" and
    .["style.theme"].aliases == ["theme", "themes"] and
    .["style.theme"].action == "theme=$(\"$HOME/.local/bin/dotfiles-omarchy-theme-switcher\"); [[ -n $theme ]] && omarchy-theme-set \"$theme\""
  ' "$menu" >/dev/null || die 'desktop menu extension routing is not exact'
}

desktop_require_adoptable_menu() {
  local path="$HOME/$DESKTOP_MENU_EXTENSION"
  local stock="${HOST_ROOT:-}/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ ! -L "$path" ]] || return 0
  if [[ -f "$path" && -f "$stock" && ! -L "$stock" ]] && cmp -s -- "$path" "$stock"; then
    die "unchanged Omarchy menu extension requires one-time adoption; remove $path, then rerun: dotfiles.sh apply desktop"
  fi
  die "menu extension contains user changes or is unexpected; manually merge $path before dotfiles.sh apply desktop"
}

desktop_require_adoptable_input() {
  local stock="${HOST_ROOT:-}/usr/share/omarchy/config/hypr/input.lua"
  validate_desktop_stock_input
  lean_inspect_attachment 0
  if [[ "$LEAN_ATTACHMENT_STATUS" == absent ]]; then
    cmp -s -- "$HOME/$DESKTOP_INPUT" "$stock" ||
      die 'desktop input differs from the accepted Omarchy baseline; run: omarchy refresh config hypr/input.lua'
  fi
}

desktop_require_xcompose() {
  local path="$HOME/$DESKTOP_XCOMPOSE"
  [[ -f "$path" && ! -L "$path" ]] ||
    die "Omarchy XCompose baseline is missing or not a regular file: $path"
}

validate_desktop_closure() {
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'omarchy/desktop' ]] ||
      die 'native desktop closure must contain only omarchy/desktop'
    validate_desktop_fragment
    validate_desktop_xcompose_aliases
    validate_desktop_theme_filter
  else
    [[ "$PROFILE_ENTRY_KIND" == validation-only && ${#PACKAGES[@]} -eq 0 ]] ||
      die 'Ubuntu desktop must be validation-only'
  fi
}

desktop_managed_links_and_markers_absent() {
  local index path
  lean_scan_packages
  for index in "${!LEAN_TARGET_PATHS[@]}"; do
    path="$HOME/${LEAN_TARGET_PATHS[index]}"
    [[ ! -e "$path" && ! -L "$path" ]] || return 1
  done
  for index in "${!LEAN_ATTACHMENT_PATHS[@]}"; do
    lean_inspect_attachment "$index"
    [[ "$LEAN_ATTACHMENT_STATUS" == absent ]] || return 1
  done
}

preflight_desktop() {
  register_desktop_area
  validate_desktop_closure
  if [[ "$SELECTED_PROFILE" == omarchy && "$MODE" == remove && ! -e "$LEAN_STATE" && ! -L "$LEAN_STATE" ]] &&
    desktop_managed_links_and_markers_absent; then
    return 0
  fi
  if [[ "$SELECTED_PROFILE" == omarchy && "$MODE" != remove ]]; then
    desktop_require_adoptable_input
    desktop_require_xcompose
    desktop_require_adoptable_menu
  fi
  lean_preflight_area "$MODE"
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}

apply_desktop() {
  register_desktop_area
  validate_desktop_closure
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    desktop_require_adoptable_input
    desktop_require_xcompose
    desktop_require_adoptable_menu
  fi
  lean_apply_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'applied desktop preferences and theme filter without restarting the Omarchy shell'
  else
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}

remove_desktop() {
  register_desktop_area
  validate_desktop_closure
  if [[ "$SELECTED_PROFILE" == omarchy && ! -e "$LEAN_STATE" && ! -L "$LEAN_STATE" ]] &&
    desktop_managed_links_and_markers_absent; then
    log 'desktop ownership is already absent; no changes made'
    return 0
  fi
  lean_remove_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'restored desktop shell idle values and removed exact desktop links and loaders'
  else
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}
