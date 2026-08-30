# Herdr area: native validation or an Ubuntu lean package-only closure.

readonly HERDR_VERSION='0.8.2'
readonly HERDR_NATIVE_PACKAGE='herdr 0.8.2-1'
readonly HERDR_SELECTOR="aqua:ogulcancelik/herdr@$HERDR_VERSION"
readonly HERDR_CONFIG='.config/herdr/config.toml'
readonly HERDR_REFERENCE='packages/upstream/reference/omarchy/config/herdr/config.toml'
readonly HERDR_UBUNTU_CONFIG='packages/ubuntu/herdr/.config/herdr/config.toml'
readonly HERDR_UBUNTU_PREAMBLE=$'onboarding = false\n\n[update]\nversion_check = false\nmanifest_check = true\n\n'
readonly HERDR_MOSHI_PATH='.config/systemd/user/moshi-hook.service.d/10-herdr-path.conf'
readonly HERDR_MOSHI_PATH_CONTENT=$'[Service]\nEnvironment=PATH=%h/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin\n'

register_herdr_area() {
  local package
  load_profile_closure herdr
  lean_begin_area herdr "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
}

herdr_package_identity() {
  local metadata owner='' recorded_path recorded_owner package
  if [[ "${DOTFILES_TESTING:-}" == 1 ]]; then
    metadata="$HOST_ROOT/var/lib/dotfiles-test/pacman-owners.tsv"
    [[ -f "$metadata" ]] || return 1
    while IFS=$'\t' read -r recorded_path recorded_owner; do
      [[ "$recorded_path" == /usr/bin/herdr ]] || continue
      [[ -z "$owner" ]] || return 1
      owner="$recorded_owner"
    done < "$metadata"
    [[ -n "$owner" ]] || return 1
    printf '%s' "$owner"
    return
  fi
  [[ -x /usr/bin/pacman ]] || return 1
  package="$(/usr/bin/pacman -Qqo -- /usr/bin/herdr 2>/dev/null)" || return 1
  [[ "$package" == herdr ]] || return 1
  /usr/bin/pacman -Q herdr 2>/dev/null
}

herdr_resolved_binary() {
  type -P herdr 2>/dev/null || true
}

validate_herdr_runtime() {
  local binary resolved version identity expected
  resolved="$(herdr_resolved_binary)"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    binary="${HOST_ROOT:-}/usr/bin/herdr"
    expected='/usr/bin/herdr'
    [[ "${DOTFILES_TESTING:-}" != 1 ]] || expected="$binary"
    [[ "$resolved" == "$expected" ]] ||
      die "native Herdr must resolve to package-owned /usr/bin/herdr, not '${resolved:-missing}'; omarchy refresh herdr or reinstall Herdr, then rerun validation"
    identity="$(herdr_package_identity 2>/dev/null || true)"
    [[ "$identity" == "$HERDR_NATIVE_PACKAGE" ]] ||
      die "native /usr/bin/herdr must be owned by package '$HERDR_NATIVE_PACKAGE', found '${identity:-no package owner}'; omarchy refresh herdr or reinstall Herdr, then rerun validation"
  else
    [[ -n "$resolved" ]] || {
      log "error: Herdr is absent; install it manually with: mise install $HERDR_SELECTOR"
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
  [[ "$version" == "herdr $HERDR_VERSION" ]] || {
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      die "native Herdr must report 'herdr $HERDR_VERSION', found '${version:-missing}'; omarchy refresh herdr or reinstall Herdr, then rerun validation"
    fi
    die "Ubuntu Herdr must report 'herdr $HERDR_VERSION', found '${version:-missing}'; install it with: mise install $HERDR_SELECTOR"
  }
  HERDR_BINARY="$binary"
}

validate_herdr_config_file() {
  local path="$1" description="$2" mode
  [[ -f "$path" && ! -L "$path" ]] || die "$description is missing or is not a regular file: $path"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "$description has an unsafe owner: $path"
  mode="$(stat -c %a -- "$path")"
  [[ "$mode" == 600 || "$mode" == 640 || "$mode" == 644 ]] || die "$description has an unsafe mode: $path"
  cmp -s -- "$path" "$DOTFILES_DIR/$HERDR_REFERENCE" || {
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      die "native Herdr config has drifted: $path; omarchy refresh herdr or reinstall Herdr, then rerun validation"
    fi
    die "Ubuntu Herdr config differs from the accepted v4 snapshot: $path"
  }
}

validate_herdr_ubuntu_derivation() {
  local reference="$DOTFILES_DIR/$HERDR_REFERENCE"
  local ubuntu_config="$DOTFILES_DIR/$HERDR_UBUNTU_CONFIG"
  [[ -f "$ubuntu_config" && ! -L "$ubuntu_config" ]] || die 'Ubuntu Herdr config is missing or unsafe'
  cmp -s -- "$ubuntu_config" <(printf '%s' "$HERDR_UBUNTU_PREAMBLE"; cat -- "$reference") ||
    die 'Ubuntu Herdr config is not the exact policy preamble plus accepted v4 snapshot'
}

validate_herdr_config_syntax() {
  local source temporary status=0
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    source="$DOTFILES_DIR/$HERDR_REFERENCE"
  else
    source="$DOTFILES_DIR/$HERDR_UBUNTU_CONFIG"
  fi
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-herdr.XXXXXX")"
  mkdir -p "$temporary/.config/herdr"
  cp -- "$source" "$temporary/.config/herdr/config.toml"
  HOME="$temporary" XDG_CONFIG_HOME="$temporary/.config" XDG_DATA_HOME="$temporary/.local/share" \
    XDG_STATE_HOME="$temporary/.local/state" XDG_CACHE_HOME="$temporary/.cache" MISE_OFFLINE=1 \
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
    lean_scan_packages
    ((${#LEAN_TARGET_PATHS[@]} == ${#expected_targets[@]})) || die 'Ubuntu Herdr package target inventory is not exact'
    for expected in "${expected_targets[@]}"; do
      array_contains "$expected" "${LEAN_TARGET_PATHS[@]}" || die "Ubuntu Herdr package is missing expected target: $expected"
    done
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
  register_herdr_area
  validate_herdr_closure
  validate_herdr_runtime
  [[ "$SELECTED_PROFILE" != omarchy ]] || validate_herdr_config_file "$HOME/$HERDR_CONFIG" 'native Herdr config'
  validate_herdr_config_syntax
  lean_apply_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'validated package-owned native Herdr; no files or deployment state were written'
  else
    log "applied Ubuntu Herdr config, helpers, and selector; install the runtime manually with: mise install $HERDR_SELECTOR"
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
  log 'removed only exact managed Herdr package links; retained logs, sessions, sockets, and runtime data'
}
