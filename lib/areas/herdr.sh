# Herdr area: native validation or an Ubuntu lean package-only closure.

readonly HERDR_VERSION='0.8.2'
readonly HERDR_NATIVE_PACKAGE='herdr 0.8.2-1'
readonly HERDR_SELECTOR="aqua:ogulcancelik/herdr@$HERDR_VERSION"
readonly HERDR_CONFIG='.config/herdr/config.toml'
readonly HERDR_REFERENCE='packages/upstream/reference/omarchy/config/herdr/config.toml'
readonly HERDR_UBUNTU_CONFIG='packages/ubuntu/herdr/.config/herdr/config.toml'
readonly HERDR_UBUNTU_PREAMBLE=$'onboarding = false\n\n[update]\nversion_check = false\nmanifest_check = true\n\n'
# The accepted snapshot ends in [ui]; append reviewed personal UI preferences.
readonly HERDR_UBUNTU_PREFERENCES=$'agent_panel_sort = "priority"\nhost_cursor = "native"\nstatus_indicators = "symbols"\n'
readonly HERDR_MOSHI_PATH='.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf'
readonly HERDR_MOSHI_PATH_CONTENT=$'[Service]\nEnvironment=PATH=%h/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin\n'

register_herdr_area() {
  local package
  load_profile_closure herdr
  lean_begin_area herdr "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
}

herdr_resolved_binary() {
  type -P herdr 2>/dev/null || true
}

validate_herdr_runtime() {
  local binary resolved version identity expected package_version
  resolved="$(herdr_resolved_binary)"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    binary="${HOST_ROOT:-}/usr/bin/herdr"
    expected='/usr/bin/herdr'
    [[ "${DOTFILES_TESTING:-}" != 1 ]] || expected="$binary"
    [[ "$resolved" == "$expected" ]] ||
      die "native Herdr must resolve to package-owned /usr/bin/herdr, not '${resolved:-missing}'; omarchy refresh herdr or reinstall Herdr, then rerun validation"
    identity="$(omarchy_package_identity /usr/bin/herdr herdr 2>/dev/null || true)"
    [[ "$identity" =~ ^herdr[[:space:]](([0-9]+:)?([0-9][0-9A-Za-z._+~]*)-[0-9]+(\.[0-9]+)*)$ ]] ||
      die "native /usr/bin/herdr must have valid package ownership and version metadata, found '${identity:-no package owner}'; reinstall Herdr, then rerun validation"
    package_version="${BASH_REMATCH[3]}"
    [[ "$identity" == "$HERDR_NATIVE_PACKAGE" ]] ||
      log_warning "native Herdr package version is unreviewed: installed=$identity recorded=$HERDR_NATIVE_PACKAGE"
  else
    [[ -n "$resolved" ]] || {
      log_error "Herdr is absent; install it manually with: mise install $HERDR_SELECTOR"
      return 1
    }
    binary="$(realpath -e -- "$resolved" 2>/dev/null || true)"
    expected="$HOME/.local/share/mise/installs/aqua-ogulcancelik-herdr/$HERDR_VERSION/herdr"
    [[ "$binary" == "$expected" ]] ||
      die "Ubuntu Herdr must resolve to the selected mise install '$expected', not '${binary:-missing}'; install it with: mise install $HERDR_SELECTOR"
  fi
  [[ -f "$binary" && ! -L "$binary" && -x "$binary" ]] ||
    die "selected Herdr runtime is not a directly executable regular file: ${binary:-missing}"
  version="$("$binary" --version 2>/dev/null || true)"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$version" == "herdr $package_version" ]] ||
      die "native Herdr runtime version does not match package metadata: runtime='${version:-missing}' package='$identity'; reinstall Herdr, then rerun validation"
  elif [[ "$version" != "herdr $HERDR_VERSION" ]]; then
    die "Ubuntu Herdr must report 'herdr $HERDR_VERSION', found '${version:-missing}'; install it with: mise install $HERDR_SELECTOR"
  fi
  HERDR_BINARY="$binary"
}

validate_herdr_config_file() {
  local path="$1" description="$2" mode result
  [[ -f "$path" && ! -L "$path" ]] || die "$description is missing or is not a regular file: $path"
  path_owned_by_euid "$path" || die "$description has an unsafe owner: $path"
  mode="$(stat -c %a -- "$path")"
  [[ "$mode" == 600 || "$mode" == 640 || "$mode" == 644 ]] || die "$description has an unsafe mode: $path"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1 ||
      die 'native Herdr config validation requires Python 3.11+ tomllib'
    result="$(python3 - "$path" <<'PY'
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as config:
        data = tomllib.load(config)
except tomllib.TOMLDecodeError:
    print("invalid-toml")
    raise SystemExit
ui = data.get("ui")
if ui is not None and not isinstance(ui, dict):
    print("invalid-ui")
elif not isinstance(ui, dict) or ui.get("status_indicators") != "symbols":
    print("preference")
else:
    print("valid")
PY
    )"
    case "$result" in
      valid) ;;
      preference) die "native Herdr preference mismatch: set status_indicators = \"symbols\" under [ui] in $path" ;;
      invalid-toml) die "native Herdr config is invalid TOML: $path" ;;
      invalid-ui) die "native Herdr config is invalid: ui must be a TOML table in $path" ;;
      *) die "native Herdr config could not be parsed safely: $path" ;;
    esac
  fi
}

validate_herdr_ubuntu_derivation() {
  local reference="$DOTFILES_DIR/$HERDR_REFERENCE"
  local ubuntu_config="$DOTFILES_DIR/$HERDR_UBUNTU_CONFIG"
  [[ -f "$ubuntu_config" && ! -L "$ubuntu_config" ]] || die 'Ubuntu Herdr config is missing or unsafe'
  cmp -s -- "$ubuntu_config" <(printf '%s' "$HERDR_UBUNTU_PREAMBLE"; cat -- "$reference"; printf '%s' "$HERDR_UBUNTU_PREFERENCES") ||
    die 'Ubuntu Herdr config is not the exact policy preamble plus accepted v4 snapshot and reviewed UI preferences'
}

validate_herdr_config_syntax() {
  local source temporary status=0
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    source="$HOME/$HERDR_CONFIG"
  else
    source="$DOTFILES_DIR/$HERDR_UBUNTU_CONFIG"
  fi
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-herdr.XXXXXX")"
  mkdir -p "$temporary/.config/herdr"
  cp -- "$source" "$temporary/.config/herdr/config.toml"
  HOME="$temporary" XDG_CONFIG_HOME="$temporary/.config" XDG_DATA_HOME="$temporary/.local/share" \
    XDG_STATE_HOME="$temporary/.local/state" XDG_CACHE_HOME="$temporary/.cache" MISE_OFFLINE=1 \
    HERDR_CONFIG_PATH="$temporary/.config/herdr/config.toml" \
    "$HERDR_BINARY" config check >/dev/null 2>&1 || status=$?
  rm -rf -- "$temporary"
  ((status == 0)) || die 'selected Herdr config failed offline herdr config check'
}

validate_herdr_closure() {
  local expected index relative source
  local selector="$DOTFILES_DIR/packages/ubuntu/herdr/.config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml"
  local -a expected_targets=(
    .config/dotfiles/bash/fns/herdr
    .config/herdr/config.toml
    .config/mise/conf.d/50-dotfiles-herdr-ubuntu.toml
    .config/systemd/user/moshi-hook.service.d/10-herdr-path.conf
  )
  [[ -f "$DOTFILES_DIR/$HERDR_REFERENCE" && ! -L "$DOTFILES_DIR/$HERDR_REFERENCE" ]] ||
    die 'accepted Herdr v4 reference config is missing'
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$PROFILE_ENTRY_KIND" == validation-only && ${#PACKAGES[@]} -eq 0 ]] ||
      die 'native Herdr must be validation-only'
  else
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'ubuntu/herdr' ]] ||
      die 'Ubuntu Herdr closure must contain only ubuntu/herdr'
    validate_herdr_ubuntu_derivation
    cmp -s -- "$DOTFILES_DIR/packages/ubuntu/herdr/$HERDR_MOSHI_PATH" \
      <(printf '%s' "$HERDR_MOSHI_PATH_CONTENT") || die 'Ubuntu Moshi Herdr PATH drop-in bytes are not exact'
    grep -qxF '"aqua:ogulcancelik/herdr" = "0.8.2"' "$selector" ||
      die 'Ubuntu Herdr mise selector is not the accepted 0.8.2 release'
    lean_scan_expected_targets 'Ubuntu Herdr package' "${expected_targets[@]}"
    for index in "${!LEAN_TARGET_PATHS[@]}"; do
      relative="${LEAN_TARGET_PATHS[index]}"
      source="${LEAN_TARGET_SOURCES[index]}"
      [[ "$(stat -c %a -- "$source")" == 644 ]] || die "unexpected Ubuntu Herdr payload mode for $relative"
    done
    bash -n "$DOTFILES_DIR/packages/ubuntu/herdr/.config/dotfiles/bash/fns/herdr" || die 'Ubuntu Herdr helpers have invalid Bash syntax'
  fi
}

preflight_herdr() {
  register_herdr_area
  validate_herdr_closure
  if [[ "$MODE" == remove ]]; then
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      validate_herdr_runtime
      validate_herdr_config_file "$HOME/$HERDR_CONFIG" 'native Herdr config'
      validate_herdr_config_syntax
    fi
    lean_preflight_area remove
    return
  fi
  validate_herdr_runtime
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    validate_home_parent_chain "$HOME/$HERDR_CONFIG"
    validate_herdr_config_file "$HOME/$HERDR_CONFIG" 'native Herdr config'
  fi
  validate_herdr_config_syntax
  lean_preflight_area "$MODE"
}

apply_herdr() {
  preflight_herdr
  lean_apply_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log_success 'validated package-owned native Herdr; no files or deployment state were written'
  else
    log_success "applied Ubuntu Herdr config, helpers, and selector; install the runtime manually with: mise install $HERDR_SELECTOR"
  fi
}

remove_herdr() {
  register_herdr_area
  validate_herdr_closure
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    validate_herdr_runtime
    validate_herdr_config_file "$HOME/$HERDR_CONFIG" 'native Herdr config'
    validate_herdr_config_syntax
  fi
  lean_remove_area
  log_success 'removed only exact managed Herdr package links; retained logs, sessions, sockets, and runtime data'
}
