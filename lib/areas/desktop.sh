# Native Omarchy desktop overrides; Ubuntu intentionally validates only.

readonly DESKTOP_INPUT='.config/hypr/input.lua'
readonly DESKTOP_INPUT_FRAGMENT='.config/dotfiles/omarchy/hypr/input.lua'
readonly DESKTOP_XCOMPOSE='.XCompose'
readonly DESKTOP_XCOMPOSE_ALIASES='.config/dotfiles/omarchy/XCompose'
readonly DESKTOP_BINDINGS='.config/hypr/bindings.lua'
readonly DESKTOP_BINDINGS_FRAGMENT='.config/dotfiles/omarchy/hypr/bindings.lua'
readonly DESKTOP_SHELL='.config/omarchy/shell.json'
readonly DESKTOP_MENU_PLUGIN='.config/omarchy/plugins/matt.menu'
readonly DESKTOP_MENU_WIDGET_POINTER='/bar/layout/left/0/id'
DESKTOP_MENU_STATE_EXPANDED=false
readonly DESKTOP_MENU_EXTENSION='.config/omarchy/extensions/omarchy-menu.jsonc'
readonly DESKTOP_MENU_SHORTCUTS='.config/dotfiles/omarchy/menu-shortcuts.jsonc'
readonly DESKTOP_THEME_SWITCHER='.local/bin/dotfiles-omarchy-theme-switcher'
readonly DESKTOP_THEME_MENU_ADAPTER='.local/libexec/dotfiles-omarchy-theme-switcher/omarchy-menu-images'
readonly DESKTOP_COMPOSE_SHORTCUT='.local/bin/dotfiles-omarchy-compose-shortcut'
readonly DESKTOP_SHORTCUTS='.local/bin/dotfiles-shortcuts'
readonly DESKTOP_WINDOWS_VM='.local/bin/dotfiles-omarchy-windows-vm'
readonly DESKTOP_WINDOWS_ENTRY='.local/share/applications/windows-vm.desktop'
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
readonly DESKTOP_BINDINGS_BEGIN='-- >>> dotfiles desktop bindings >>>'
readonly DESKTOP_BINDINGS_END='-- <<< dotfiles desktop bindings <<<'
readonly DESKTOP_BINDINGS_TOKEN='dotfiles desktop bindings'
readonly DESKTOP_BINDINGS_BLOCK="$DESKTOP_BINDINGS_BEGIN
local home = os.getenv(\"HOME\")
if home and home ~= \"\" then
  local fragment = home .. \"/$DESKTOP_BINDINGS_FRAGMENT\"
  local handle = io.open(fragment, \"r\")
  if handle then
    handle:close()
    dofile(fragment)
  end
end
$DESKTOP_BINDINGS_END"
readonly DESKTOP_MENU_BEGIN='  // >>> dotfiles desktop menu theme >>>'
readonly DESKTOP_MENU_END='  // <<< dotfiles desktop menu theme <<<'
readonly DESKTOP_MENU_TOKEN='dotfiles desktop menu theme'
readonly DESKTOP_MENU_ACTION='theme=$("$HOME/.local/bin/dotfiles-omarchy-theme-switcher"); [[ -n $theme ]] && omarchy-theme-set "$theme"'
readonly DESKTOP_MENU_LEGACY_BLOCK='  // >>> dotfiles desktop menu theme >>>
  "style.theme": {"icon":"󰸌","label":"Theme","aliases":["theme","themes"],"action":"theme=$(\"$HOME/.local/bin/dotfiles-omarchy-theme-switcher\"); [[ -n $theme ]] && omarchy-theme-set \"$theme\""},
  "shortcuts": {"icon":"󰌌","label":"Shortcuts","aliases":["shortcut","shortcuts"]},
  "shortcuts.space": {"label":"Space"},
  "shortcuts.space.a": {"label":"a · AGENTS.md","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" space-a"},
  "shortcuts.prompts": {"label":"p · Prompts"},
  "shortcuts.prompts.b": {"label":"b · Continue briefly","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-b"},
  "shortcuts.prompts.d": {"label":"d · Discuss unresolved points","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-d"},
  "shortcuts.prompts.t": {"label":"t · Ask for recommendation","action":"\"$HOME/.local/bin/dotfiles-omarchy-compose-shortcut\" p-t"},
  // <<< dotfiles desktop menu theme <<<'

desktop_menu_block() {
  printf '%s\n' "$DESKTOP_MENU_BEGIN"
  printf '%s\n' '  "remove.windows": {"when":"false"},'
  printf '%s\n' '  "style.theme": {"icon":"󰸌","label":"Theme","aliases":["theme","themes"],"action":"theme=$(\"$HOME/.local/bin/dotfiles-omarchy-theme-switcher\"); [[ -n $theme ]] && omarchy-theme-set \"$theme\""},'
  cat "$DOTFILES_DIR/packages/omarchy/desktop/$DESKTOP_MENU_SHORTCUTS"
  printf '%s\n' "$DESKTOP_MENU_END"
}

desktop_shell_state_is_pre_plugin() {
  [[ -f "$LEAN_STATE" && ! -L "$LEAN_STATE" ]] || return 1
  jq -e --arg path "$DESKTOP_SHELL" '
    (.version == 2 or .version == 3) and .area == "desktop" and .profile == "omarchy" and
    (.resources | keys) == [$path] and
    .resources[$path].id == "desktop-shell-idle-v1" and
    (.resources[$path].fields | keys) == ["/idle/lock", "/idle/screensaver"]
  ' "$LEAN_STATE" >/dev/null 2>&1
}

register_desktop_area() {
  local package menu_block
  load_profile_closure desktop
  lean_begin_area desktop "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    menu_block="$(desktop_menu_block)"
    lean_add_guarded_attachment desktop-input-v1 "$DESKTOP_INPUT" \
      "$DESKTOP_INPUT_BEGIN" "$DESKTOP_INPUT_END" "$DESKTOP_INPUT_TOKEN" \
      "$DESKTOP_INPUT_BLOCK" append 0644 true
    lean_add_guarded_attachment desktop-xcompose-v1 "$DESKTOP_XCOMPOSE" \
      "$DESKTOP_XCOMPOSE_BEGIN" "$DESKTOP_XCOMPOSE_END" "$DESKTOP_XCOMPOSE_TOKEN" \
      "$DESKTOP_XCOMPOSE_BLOCK" append 0644 true
    lean_add_guarded_attachment desktop-menu-theme-v1 "$DESKTOP_MENU_EXTENSION" \
      "$DESKTOP_MENU_BEGIN" "$DESKTOP_MENU_END" "$DESKTOP_MENU_TOKEN" \
      "$menu_block" after-exact 0644 true '{' "$DESKTOP_MENU_LEGACY_BLOCK"
    lean_add_guarded_attachment desktop-bindings-v1 "$DESKTOP_BINDINGS" \
      "$DESKTOP_BINDINGS_BEGIN" "$DESKTOP_BINDINGS_END" "$DESKTOP_BINDINGS_TOKEN" \
      "$DESKTOP_BINDINGS_BLOCK" append 0644 true
    if [[ "$MODE" == apply && "$DESKTOP_MENU_STATE_EXPANDED" != true ]] && desktop_shell_state_is_pre_plugin; then
      lean_add_json_scalar_fields desktop-shell-idle-v1 "$DESKTOP_SHELL" validate_desktop_shell_json \
        /idle/screensaver integer 600 /idle/lock integer 900
    else
      lean_add_json_scalar_fields desktop-shell-idle-v1 "$DESKTOP_SHELL" validate_desktop_shell_json \
        /idle/screensaver integer 600 /idle/lock integer 900 \
        "$DESKTOP_MENU_WIDGET_POINTER" string '"matt.menu"'
    fi
  fi
}

validate_desktop_shortcuts() {
  local package="$DOTFILES_DIR/packages/omarchy/desktop" helper fragment launcher menu expected_binding
  helper="$package/$DESKTOP_COMPOSE_SHORTCUT"
  fragment="$package/$DESKTOP_BINDINGS_FRAGMENT"
  launcher="$package/$DESKTOP_SHORTCUTS"
  menu="$package/$DESKTOP_MENU_SHORTCUTS"
  [[ -f "$helper" && ! -L "$helper" && -x "$helper" && "$(stat -c %a -- "$helper")" == 755 ]] ||
    die 'desktop Compose shortcut helper is not an accepted executable payload'
  bash -n "$helper" || die 'desktop Compose shortcut helper has invalid Bash syntax'
  expected_binding="$(jq -r \
    '"o.bind(\(.binding.keys | tojson), \(.binding.description | tojson), \"omarchy-menu toggle shortcuts\")"' \
    "$DOTFILES_DIR/manifests/desktop-shortcuts.json")" || die 'desktop shortcut manifest binding is unreadable'
  [[ -f "$fragment" && ! -L "$fragment" && "$(< "$fragment")" == "$expected_binding" ]] ||
    die 'desktop shortcut binding fragment is not exact'
  [[ -f "$menu" && ! -L "$menu" ]] || die 'desktop shortcut menu fragment is missing or unsafe'
  [[ -f "$launcher" && ! -L "$launcher" && -x "$launcher" && "$(stat -c %a -- "$launcher")" == 755 ]] ||
    die 'desktop shortcut manager launcher is not an accepted executable payload'
  bash -n "$launcher" || die 'desktop shortcut manager launcher has invalid Bash syntax'
  if [[ "${DOTFILES_SHORTCUTS_MIGRATE_STATE:-}" != 1 ]] || ! desktop_hashless_state_migration_allowed; then
    "$DOTFILES_DIR/scripts/generate-desktop-shortcuts" || die 'desktop shortcut generated files are stale'
  fi
}

desktop_hashless_state_migration_allowed() {
  local index relative recorded_id status
  [[ -f "$LEAN_STATE" && ! -L "$LEAN_STATE" ]] || return 1
  lean_validate_state_file "$LEAN_STATE"
  [[ "$(jq -r .version "$LEAN_STATE")" =~ ^[12]$ ]] || return 1
  [[ "$(jq '.attachments | length' "$LEAN_STATE")" == "${#LEAN_ATTACHMENT_PATHS[@]}" ]] || return 1
  for index in "${!LEAN_ATTACHMENT_PATHS[@]}"; do
    relative="${LEAN_ATTACHMENT_PATHS[index]}"
    recorded_id="$(jq -er --arg path "$relative" '.attachments[$path].id' "$LEAN_STATE" 2>/dev/null)" || return 1
    [[ "$recorded_id" == "${LEAN_ATTACHMENT_IDS[index]}" ]] || return 1
    lean_inspect_attachment "$index"
    status="$LEAN_ATTACHMENT_STATUS"
    [[ "$status" == hashless ]] || return 1
  done
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
    (.idle.lock | type == "number" and floor == .) and
    (.bar.layout.left | type == "array" and length > 0) and
    (.bar.layout.left[0].id == "omarchy.menu" or .bar.layout.left[0].id == "matt.menu") and
    ([.bar.layout | .left[], .center[], .right[] | select(.id == "omarchy.menu" or .id == "matt.menu")] | length) == 1
  ' "$1" >/dev/null
}

desktop_require_menu_plugin_adoptable() {
  local live path="$HOME/$DESKTOP_SHELL"
  validate_desktop_shell_json "$path" || die "JSON resource has an unsupported application shape: $path"
  live="$(lean_json_pointer_value "$path" "$DESKTOP_MENU_WIDGET_POINTER")" ||
    die 'Omarchy menu widget is missing from the supported left bar position'
  if [[ ! -e "$LEAN_STATE" && ! -L "$LEAN_STATE" && "$live" != '"omarchy.menu"' ]]; then
    die 'Omarchy menu widget already uses an unmanaged clone'
  fi
}

# Apply alone expands the exact prior desktop resource record. Check/remove
# keep refusing incomplete state, matching guarded attachment migrations.
desktop_expand_menu_plugin_state() {
  local shell_path="$HOME/$DESKTOP_SHELL" temporary mode live source_hash source_identity temporary_hash temporary_identity
  [[ -f "$LEAN_STATE" && ! -L "$LEAN_STATE" ]] || return 0
  lean_validate_state_file "$LEAN_STATE"
  desktop_shell_state_is_pre_plugin || return 0
  live="$(lean_json_pointer_value "$shell_path" "$DESKTOP_MENU_WIDGET_POINTER")"
  DESKTOP_MENU_STATE_EXPANDED=true
  if [[ "$live" == '"omarchy.menu"' ]]; then
    register_desktop_area
    LEAN_JSON_STATUSES=(original)
    lean_replace_json_resource 0 managed
  fi
  source_hash="$(sha256_file "$LEAN_STATE")"
  capture_path_object_identity "$LEAN_STATE" || die "could not inspect lean state identity: $LEAN_STATE"
  source_identity="$PATH_OBJECT_IDENTITY"
  mode="$(stat -c %a -- "$LEAN_STATE")"
  temporary="$(mktemp "$(dirname -- "$LEAN_STATE")/.desktop-state.tmp.XXXXXX")"
  track_temp_path "$temporary"
  temporary_identity="$PATH_OBJECT_IDENTITY"
  jq --arg path "$DESKTOP_SHELL" --arg pointer "$DESKTOP_MENU_WIDGET_POINTER" '
    .resources[$path].fields[$pointer] = {
      type: "string", original: "omarchy.menu", managed: "matt.menu"
    }
  ' "$LEAN_STATE" > "$temporary"
  chmod "$mode" "$temporary"
  temporary_hash="$(sha256_file "$temporary")"
  lean_publish_temp 'lean state' lean-before-state-rename "$temporary" "$temporary_identity" "$temporary_hash" \
    "$LEAN_STATE" "$source_identity" "$source_hash"
  lean_validate_state_file "$LEAN_STATE"
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
  local package="$DOTFILES_DIR/packages/omarchy/desktop" selector adapter hidden
  selector="$package/$DESKTOP_THEME_SWITCHER"
  adapter="$package/$DESKTOP_THEME_MENU_ADAPTER"
  [[ -f "$selector" && ! -L "$selector" && -x "$selector" && "$(stat -c %a -- "$selector")" == 755 ]] ||
    die 'desktop theme selector is not an accepted executable payload'
  bash -n "$selector" || die 'desktop theme selector has invalid Bash syntax'
  [[ -f "$adapter" && ! -L "$adapter" && -x "$adapter" && "$(stat -c %a -- "$adapter")" == 755 ]] ||
    die 'desktop theme image adapter is not an accepted executable payload'
  bash -n "$adapter" || die 'desktop theme image adapter has invalid Bash syntax'
  mapfile -t hidden < <(awk '/^readonly -a HIDDEN_THEMES=\($/{inside=1; next} inside && /^\)/{exit} inside {sub(/^[[:space:]]+/, ""); print}' "$selector")
  [[ "$(printf '%s\n' "${hidden[@]}")" == "$(< "$DOTFILES_DIR/manifests/hidden-themes.txt")" ]] ||
    die 'desktop theme selector denylist is not exact'
}

desktop_menu_json() {
  jq -eRsc '
    gsub("(?m)^\\s*//[^\\n]*(\\n|$)"; "") |
    gsub(",(?<close>\\s*[}\\]])"; "\(.close)") |
    fromjson
  ' "$1"
}

validate_desktop_menu() {
  local path="$HOME/$DESKTOP_MENU_EXTENSION"
  local first last status
  validate_home_parent_chain "$path"
  if [[ "$MODE" == remove && ! -e "$path" && ! -L "$path" ]]; then return 0; fi
  [[ -f "$path" && ! -L "$path" && "$(stat -c %u -- "$path")" == "$EUID" ]] ||
    die "Omarchy menu extension is not an EUID-owned regular file: $path"
  file_contains_nul "$path" && die "Omarchy menu extension contains NUL bytes: $path"
  [[ "$(grep -cFx -- '{' "$path")" == 1 ]] || die "Omarchy menu extension has an ambiguous opening anchor: $path"
  first="$(awk '!/^[[:space:]]*\/\// && NF {print; exit}' "$path")"
  last="$(awk '!/^[[:space:]]*\/\// && NF {line=$0} END {print line}' "$path")"
  [[ "$first" == '{' && "$last" == '}' ]] || die "Omarchy menu extension is not a top-level compatible JSONC object: $path"
  desktop_menu_json "$path" | jq -e '
    type == "object" and (has("items") | not) and
    all(to_entries[]; .value | type == "object")
  ' >/dev/null 2>&1 ||
    die "Omarchy menu extension is malformed or incompatible: $path"
  lean_inspect_attachment "$(lean_attachment_index desktop-menu-theme-v1)"
  status="$LEAN_ATTACHMENT_STATUS"
  [[ "$status" != malformed ]] || die "guarded attachment is partial, malformed, duplicate, or modified: $path"
  if [[ "$status" == legacy ]]; then
    [[ "$MODE" == apply || "$MODE" == remove ]] || die "guarded attachment differs from the current managed version: $path"
  elif [[ "$status" == deployed || "$status" == pending || "$status" == transitioned ]]; then
    [[ "$MODE" != check ]] || die "guarded attachment differs from the current managed version: $path"
  fi
  if [[ "$status" == exact || "$status" == hashless || "$status" == legacy || "$status" == deployed ||
    "$status" == pending || "$status" == transitioned ]]; then
    desktop_menu_json "$path" | jq -e --arg action "$DESKTOP_MENU_ACTION" '
      .["style.theme"] == {icon:"󰸌",label:"Theme",aliases:["theme","themes"],action:$action}
    ' >/dev/null || die "managed Style > Theme action differs: $path"
  else
    desktop_menu_json "$path" | jq -e '
      (has("style.theme") | not) and (has("remove.windows") | not) and
      (all(keys[]; . != "shortcuts" and (startswith("shortcuts.") | not)))
    ' >/dev/null || die "Omarchy menu extension already has an unmanaged desktop route: $path"
  fi
}

desktop_require_bindings() {
  local path="$HOME/$DESKTOP_BINDINGS" status binding_keys keys_pattern
  [[ -f "$path" && ! -L "$path" ]] || die "Omarchy bindings baseline is missing or not a regular file: $path"
  lean_inspect_attachment "$(lean_attachment_index desktop-bindings-v1)"
  status="$LEAN_ATTACHMENT_STATUS"
  [[ "$status" != malformed ]] || die "guarded attachment is partial, malformed, duplicate, or modified: $path"
  binding_keys="$(jq -r '.binding.keys' "$DOTFILES_DIR/manifests/desktop-shortcuts.json")" ||
    die 'desktop shortcut manifest binding is unreadable'
  keys_pattern="${binding_keys//+/\\+}"
  keys_pattern="${keys_pattern// /[[:space:]]*}"
  if [[ "$status" == absent ]] && grep -Eq \
    "^[[:space:]]*(o|hl)\\.bind[[:space:]]*\\([[:space:]]*[\"']${keys_pattern}[\"']" "$path"; then
    die "Omarchy bindings already contain an unmanaged $binding_keys: $path"
  fi
}

validate_desktop_stock_menu() {
  local stock="${HOST_ROOT:-}/usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc" installed_identity stock_identity
  [[ -f "$stock" && ! -L "$stock" ]] || die "Omarchy stock menu baseline is missing or unsafe: $stock"
  installed_identity="$(omarchy_package_identity /usr/share/omarchy/version 2>/dev/null || true)"
  stock_identity="$(omarchy_package_identity /usr/share/omarchy/config/omarchy/extensions/omarchy-menu.jsonc omarchy-settings 2>/dev/null || true)"
  [[ -n "$stock_identity" && "${stock_identity#omarchy-settings }" == "${installed_identity#omarchy }" ]] ||
    die 'Omarchy stock menu baseline package identity does not match authoritative Omarchy'
}

desktop_require_adoptable_input() {
  local stock="${HOST_ROOT:-}/usr/share/omarchy/config/hypr/input.lua"
  validate_desktop_stock_input
  lean_inspect_attachment "$(lean_attachment_index desktop-input-v1)"
  if [[ "$LEAN_ATTACHMENT_STATUS" == absent ]]; then
    cmp -s -- "$HOME/$DESKTOP_INPUT" "$stock" ||
      die 'desktop input differs from the accepted Omarchy baseline; run: omarchy refresh config hypr/input.lua'
  fi
}

desktop_require_xcompose() {
  local path="$HOME/$DESKTOP_XCOMPOSE"
  [[ -f "$path" && ! -L "$path" ]] ||
    die "Omarchy XCompose baseline is missing or not a regular file: $path"
  grep -Eq '^[[:space:]]*include[[:space:]]+"/usr/share/omarchy/default/xcompose"[[:space:]]*$' "$path" ||
    die "Omarchy XCompose baseline lacks its packaged default include: $path"
}

desktop_require_native_shortcuts() {
  local source id multi prefix key path pattern
  while IFS=$'\t' read -r source id multi prefix key; do
    case "$source" in
      host) path="$HOME/$DESKTOP_XCOMPOSE" ;;
      omarchy) path="${HOST_ROOT:-}/usr/share/omarchy/default/xcompose" ;;
      *) die "desktop shortcut manifest returned an unsupported native source: $source" ;;
    esac
    [[ -f "$path" && ! -L "$path" ]] ||
      die "desktop shortcut native source is missing or unsafe for $id: $path"
    pattern="^[[:space:]]*<$multi>[[:space:]]+<$prefix>[[:space:]]+<$key>[[:space:]]*:"
    if [[ "$source" == host ]]; then
      awk -v begin="$DESKTOP_XCOMPOSE_BEGIN" -v end="$DESKTOP_XCOMPOSE_END" '
        $0 == begin { managed=1; next }
        $0 == end { managed=0; next }
        !managed
      ' "$path" | grep -Eq "$pattern" ||
        die "desktop shortcut native reference is missing outside the managed include: $id"
    else
      grep -Eq "$pattern" "$path" || die "desktop shortcut native reference is missing: $id"
    fi
  done < <("$DOTFILES_DIR/scripts/generate-desktop-shortcuts" --native-references)
}

validate_desktop_closure() {
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'omarchy/desktop' ]] ||
      die 'native desktop closure must contain only omarchy/desktop'
    validate_desktop_fragment
    validate_desktop_shortcuts
    validate_desktop_theme_filter
    local wrapper="$DOTFILES_DIR/packages/omarchy/desktop/$DESKTOP_WINDOWS_VM"
    local entry="$DOTFILES_DIR/packages/omarchy/desktop/$DESKTOP_WINDOWS_ENTRY"
    [[ -f "$wrapper" && ! -L "$wrapper" && "$(stat -c %a -- "$wrapper")" == 755 ]] ||
      die 'desktop Windows VM wrapper is not an accepted executable payload'
    bash -n "$wrapper" || die 'desktop Windows VM wrapper has invalid Bash syntax'
    [[ -f "$entry" && ! -L "$entry" && "$(stat -c %a -- "$entry")" == 644 &&
      "$(< "$entry")" == '[Desktop Entry]
Name=Windows
Comment=Safely launch Windows VM and keep it running after RDP disconnects
Exec=uwsm app -- dotfiles-omarchy-windows-vm
Icon=windows
Terminal=false
Type=Application
Categories=System;Emulator;' ]] || die 'desktop Windows VM entry is not exact'
    [[ -f "$DOTFILES_DIR/packages/omarchy/desktop/$DESKTOP_MENU_PLUGIN/manifest.json" ]] ||
      die 'desktop menu plugin clone is missing'
    if [[ "$MODE" != remove ]]; then validate_desktop_stock_menu; fi
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    if [[ "$MODE" != remove ]]; then
      desktop_require_adoptable_input
      desktop_require_xcompose
      desktop_require_native_shortcuts
      desktop_require_bindings
      desktop_require_menu_plugin_adoptable
    fi
    validate_desktop_menu
  fi
  lean_preflight_area "$MODE"
  if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}

apply_desktop() {
  preflight_desktop
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    desktop_expand_menu_plugin_state
    register_desktop_area
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
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then validate_desktop_menu; fi
  lean_remove_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'restored desktop shell idle values and removed exact desktop links and loaders'
  else
    log 'Omarchy desktop configuration is outside the Ubuntu profile; no changes made'
  fi
}
