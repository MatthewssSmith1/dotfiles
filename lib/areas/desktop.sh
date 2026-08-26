# Native Omarchy desktop overrides; Ubuntu intentionally validates only.

readonly DESKTOP_INPUT='.config/hypr/input.lua'
readonly DESKTOP_INPUT_FRAGMENT='.config/dotfiles/omarchy/hypr/input.lua'
readonly DESKTOP_SHELL='.config/omarchy/shell.json'
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

register_desktop_area() {
  local package
  load_profile_closure desktop
  lean_begin_area desktop "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    lean_add_guarded_attachment desktop-input-v1 "$DESKTOP_INPUT" \
      "$DESKTOP_INPUT_BEGIN" "$DESKTOP_INPUT_END" "$DESKTOP_INPUT_TOKEN" \
      "$DESKTOP_INPUT_BLOCK" append 0644 true
    lean_add_json_scalar_fields desktop-shell-idle-v1 "$DESKTOP_SHELL" validate_desktop_shell_json \
      /idle/screensaver integer 600 /idle/lock integer 900
  fi
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
  local installed_identity stock_identity
  [[ -f "$stock" && ! -L "$stock" ]] || die "Omarchy stock input baseline is missing or unsafe: $stock"
  installed_identity="$(omarchy_package_identity /usr/share/omarchy/version 2>/dev/null || true)"
  stock_identity="$(omarchy_package_identity /usr/share/omarchy/config/hypr/input.lua 2>/dev/null || true)"
  [[ -n "$installed_identity" && "$stock_identity" == "$installed_identity" ]] ||
    die 'Omarchy stock input baseline does not have the accepted core package identity'
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

validate_desktop_closure() {
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'omarchy/desktop' ]] ||
      die 'native desktop closure must contain only omarchy/desktop'
    validate_desktop_fragment
  else
    [[ "$PROFILE_ENTRY_KIND" == validation-only && ${#PACKAGES[@]} -eq 0 ]] ||
      die 'Ubuntu desktop must be validation-only'
  fi
}

preflight_desktop() {
  register_desktop_area
  validate_desktop_closure
  if [[ "$SELECTED_PROFILE" == omarchy && "$MODE" != remove ]]; then
    desktop_require_adoptable_input
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
  fi
  lean_apply_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'applied desktop natural-scroll loader and shell idle values without restarting the Omarchy shell'
  else
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}

remove_desktop() {
  register_desktop_area
  validate_desktop_closure
  lean_remove_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'restored desktop shell idle values and removed exact desktop links and loader'
  else
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}
