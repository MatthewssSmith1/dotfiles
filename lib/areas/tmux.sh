# tmux area: native validation or an Ubuntu lean package-only closure.

readonly TMUX_VERSION='3.7c'
readonly TMUX_NATIVE_PACKAGE='tmux 3.7_c-1'
readonly TMUX_SELECTOR="aqua:tmux/tmux-builds@$TMUX_VERSION"
readonly TMUX_CONFIG='.config/tmux/tmux.conf'
readonly TMUX_BASELINE='packages/upstream/tmux/.config/dotfiles/upstream/tmux/tmux.conf'
readonly TMUX_UBUNTU_ROOT='packages/ubuntu/tmux'

register_tmux_area() {
  local package
  load_profile_closure tmux
  lean_begin_area tmux "$SELECTED_PROFILE" "$PROFILE_ENTRY_KIND"
  for package in "${PACKAGES[@]}"; do lean_add_package "$package"; done
}

tmux_version_from_output() {
  [[ "$1" =~ ^tmux[[:space:]]+([^[:space:]]+)$ ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

tmux_version_at_least_3_5() {
  [[ "$1" =~ ^([0-9]+)\.([0-9]+)[a-z]?$ ]] || return 1
  ((10#${BASH_REMATCH[1]} > 3 ||
    (10#${BASH_REMATCH[1]} == 3 && 10#${BASH_REMATCH[2]} >= 5)))
}

tmux_native_package_identity() {
  local metadata owner='' recorded_path recorded_owner package
  if [[ "${DOTFILES_TESTING:-}" == 1 ]]; then
    metadata="$HOST_ROOT/var/lib/dotfiles-test/pacman-owners.tsv"
    [[ -f "$metadata" ]] || return 1
    while IFS=$'\t' read -r recorded_path recorded_owner; do
      [[ "$recorded_path" == /usr/bin/tmux ]] || continue
      [[ -z "$owner" ]] || return 1
      owner="$recorded_owner"
    done < "$metadata"
    [[ -n "$owner" ]] || return 1
    printf '%s' "$owner"
    return
  fi
  [[ -x /usr/bin/pacman ]] || return 1
  package="$(/usr/bin/pacman -Qqo -- /usr/bin/tmux 2>/dev/null)" || return 1
  [[ "$package" == tmux ]] || return 1
  /usr/bin/pacman -Q tmux 2>/dev/null
}

tmux_ubuntu_distro_owned() {
  local binary="$1" owner
  if [[ "${DOTFILES_TESTING:-}" == 1 ]]; then
    [[ "${DOTFILES_TEST_TMUX_OWNER:-}" == distro:tmux ]]
    return
  fi
  [[ "$binary" == /usr/bin/tmux && -x /usr/bin/dpkg-query ]] || return 1
  owner="$(/usr/bin/dpkg-query -S /usr/bin/tmux 2>/dev/null || true)"
  [[ "$owner" == 'tmux: /usr/bin/tmux' || "$owner" == tmux:*': /usr/bin/tmux' ]]
}

validate_tmux_runtime() {
  local selected expected output version identity
  selected="${DOTFILES_TEST_TMUX_BIN:-$(type -P tmux 2>/dev/null || true)}"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    expected="${HOST_ROOT:-}/usr/bin/tmux"
    [[ "$selected" == "$expected" ]] ||
      die "native tmux must resolve to package-owned /usr/bin/tmux, not '${selected:-missing}'; run omarchy refresh tmux or reinstall tmux, then rerun validation"
    identity="$(tmux_native_package_identity 2>/dev/null || true)"
    [[ "$identity" == "$TMUX_NATIVE_PACKAGE" ]] ||
      die "native /usr/bin/tmux must be owned by package '$TMUX_NATIVE_PACKAGE', found '${identity:-no package owner}'; run omarchy refresh tmux or reinstall tmux, then rerun validation"
  else
    [[ -n "$selected" ]] || {
      log "error: tmux is absent; install it manually with: mise install $TMUX_SELECTOR"
      return 1
    }
  fi
  [[ -f "$selected" && ! -L "$selected" && -x "$selected" ]] ||
    die "selected tmux runtime is not a directly executable regular file: ${selected:-missing}"
  output="$(env -u TMUX "$selected" -V 2>/dev/null || true)"
  version="$(tmux_version_from_output "$output" 2>/dev/null || true)"
  [[ -n "$version" ]] || die "selected tmux returned an invalid version: ${output:-missing}"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$version" == "$TMUX_VERSION" ]] ||
      die "native tmux must report 'tmux $TMUX_VERSION', found '$output'; run omarchy refresh tmux or reinstall tmux, then rerun validation"
  elif [[ "$selected" == "${HOST_ROOT:-}/usr/bin/tmux" ]] && tmux_ubuntu_distro_owned "$selected"; then
    tmux_version_at_least_3_5 "$version" ||
      die "Ubuntu package tmux $version is older than 3.5; install the accepted fallback with: mise install $TMUX_SELECTOR"
  else
    [[ "$version" == "$TMUX_VERSION" ]] ||
      die "Ubuntu tmux must be approved package-owned /usr/bin/tmux >=3.5 or report 'tmux $TMUX_VERSION'; install the accepted fallback with: mise install $TMUX_SELECTOR"
  fi
  TMUX_BINARY="$selected"
}

validate_tmux_config_file() {
  local path="$1" description="$2" mode guidance=''
  [[ "$SELECTED_PROFILE" != omarchy ]] || guidance='; run omarchy refresh tmux or reinstall tmux, then rerun validation'
  [[ -f "$path" && ! -L "$path" ]] || die "$description is missing or is not a regular file: $path$guidance"
  [[ "$(stat -c %u -- "$path")" == "$EUID" ]] || die "$description has an unsafe owner: $path$guidance"
  mode="$(stat -c %a -- "$path")"
  [[ "$mode" == 600 || "$mode" == 640 || "$mode" == 644 ]] || die "$description has an unsafe mode: $path$guidance"
  cmp -s -- "$path" "$DOTFILES_DIR/$TMUX_BASELINE" || {
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      die "native tmux config has drifted: $path; run omarchy refresh tmux or reinstall tmux, then rerun validation"
    fi
    die "Ubuntu tmux baseline differs from the accepted v4 snapshot: $path"
  }
}

validate_tmux_static_contract() {
  local baseline="$DOTFILES_DIR/$TMUX_BASELINE"
  local adapter="$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/dotfiles/tmux/ubuntu.conf"
  local dispatcher="$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/tmux/tmux.conf"
  local help="$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/dotfiles/tmux/keybindings.txt"
  grep -qxF 'set -g prefix C-Space' "$baseline" || die 'accepted tmux baseline lost the C-Space prefix'
  grep -qxF 'set -g prefix2 C-b' "$baseline" || die 'accepted tmux baseline lost the C-b prefix'
  grep -qxF 'set -g default-terminal "tmux-256color"' "$baseline" || die 'accepted tmux baseline lost tmux-256color'
  [[ "$SELECTED_PROFILE" != ubuntu ]] || {
    grep -qxF 'source-file ~/.config/dotfiles/upstream/tmux/tmux.conf' "$dispatcher" || die 'Ubuntu tmux dispatcher does not load the accepted baseline'
    grep -qxF 'source-file ~/.config/dotfiles/tmux/ubuntu.conf' "$dispatcher" || die 'Ubuntu tmux dispatcher does not load its adapter'
    grep -Fq 'unbind-key ?' "$adapter" || die 'Ubuntu tmux adapter does not replace the stock help binding'
    grep -Fq 'bind-key -N "Show Tmux keybindings" ? display-popup' "$adapter" || die 'Ubuntu tmux adapter has no portable popup binding'
    grep -Fq '.config/dotfiles/tmux/keybindings.txt' "$adapter" || die 'Ubuntu tmux popup does not render repository-owned help'
    ! grep -Fq 'omarchy-menu-tmux-keybindings' "$adapter" || die 'Ubuntu tmux adapter still invokes an Omarchy-only command'
    [[ -s "$help" ]] || die 'Ubuntu tmux static keybinding help is missing'
  }
}

validate_tmux_closure() {
  local expected index relative source selector
  local -a expected_targets=(
    .config/dotfiles/upstream/tmux/tmux.conf
    .config/dotfiles/tmux/keybindings.txt
    .config/dotfiles/tmux/ubuntu.conf
    .config/mise/conf.d/50-dotfiles-tmux-ubuntu.toml
    .config/tmux/tmux.conf
  )
  [[ -f "$DOTFILES_DIR/$TMUX_BASELINE" && ! -L "$DOTFILES_DIR/$TMUX_BASELINE" ]] || die 'accepted tmux v4 snapshot is missing'
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    [[ "$PROFILE_ENTRY_KIND" == validation-only && ${#PACKAGES[@]} -eq 0 ]] || die 'native tmux must be validation-only'
  else
    [[ "$PROFILE_ENTRY_KIND" == packages && "${PACKAGES[*]}" == 'upstream/tmux ubuntu/tmux' ]] ||
      die 'Ubuntu tmux closure must contain only upstream/tmux and ubuntu/tmux'
    selector="$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/mise/conf.d/50-dotfiles-tmux-ubuntu.toml"
    grep -qxF '"aqua:tmux/tmux-builds" = "3.7c"' "$selector" || die 'Ubuntu tmux mise selector is not the accepted 3.7c release'
    lean_scan_packages
    ((${#LEAN_TARGET_PATHS[@]} == ${#expected_targets[@]})) || die 'Ubuntu tmux package target inventory is not exact'
    for expected in "${expected_targets[@]}"; do
      array_contains "$expected" "${LEAN_TARGET_PATHS[@]}" || die "Ubuntu tmux package is missing expected target: $expected"
    done
    for index in "${!LEAN_TARGET_PATHS[@]}"; do
      relative="${LEAN_TARGET_PATHS[index]}"; source="${LEAN_TARGET_SOURCES[index]}"
      [[ "$(stat -c %a -- "$source")" == 644 ]] || die "unexpected Ubuntu tmux payload mode for $relative"
    done
  fi
  validate_tmux_static_contract
}

validate_tmux_parse() (
  local temporary socket_name config output status=0
  temporary="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux.XXXXXX")"
  socket_name="dotfiles-$$-$RANDOM"
  trap 'env -u TMUX HOME="$temporary/home" TMUX_TMPDIR="$temporary/socket" "$TMUX_BINARY" -L "$socket_name" kill-server >/dev/null 2>&1 || true; rm -rf -- "$temporary"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir -p "$temporary/home/.config/tmux" "$temporary/home/.config/dotfiles/upstream/tmux" \
    "$temporary/home/.config/dotfiles/tmux" "$temporary/socket"
  cp -- "$DOTFILES_DIR/$TMUX_BASELINE" "$temporary/home/.config/dotfiles/upstream/tmux/tmux.conf"
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    config="$temporary/home/.config/tmux/tmux.conf"
    cp -- "$DOTFILES_DIR/$TMUX_BASELINE" "$config"
  else
    config="$temporary/home/.config/tmux/tmux.conf"
    cp -- "$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/tmux/tmux.conf" "$config"
    cp -- "$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/dotfiles/tmux/ubuntu.conf" "$temporary/home/.config/dotfiles/tmux/ubuntu.conf"
    cp -- "$DOTFILES_DIR/$TMUX_UBUNTU_ROOT/.config/dotfiles/tmux/keybindings.txt" "$temporary/home/.config/dotfiles/tmux/keybindings.txt"
  fi
  if ! env -u TMUX HOME="$temporary/home" TMUX_TMPDIR="$temporary/socket" TERM=xterm-256color \
    "$TMUX_BINARY" -L "$socket_name" -f "$config" new-session -d -s dotfiles-validation; then
    status=1
  fi
  if ((status == 0)); then
    output="$(env -u TMUX HOME="$temporary/home" TMUX_TMPDIR="$temporary/socket" "$TMUX_BINARY" -L "$socket_name" show-options -gv prefix 2>/dev/null || true)"
    [[ "$output" == C-Space ]] || status=1
    output="$(env -u TMUX HOME="$temporary/home" TMUX_TMPDIR="$temporary/socket" "$TMUX_BINARY" -L "$socket_name" show-options -gv prefix2 2>/dev/null || true)"
    [[ "$output" == C-b ]] || status=1
    output="$(env -u TMUX HOME="$temporary/home" TMUX_TMPDIR="$temporary/socket" "$TMUX_BINARY" -L "$socket_name" show-options -gv default-terminal 2>/dev/null || true)"
    [[ "$output" == tmux-256color ]] || status=1
    if [[ "$SELECTED_PROFILE" == ubuntu ]]; then
      output="$(env -u TMUX HOME="$temporary/home" TMUX_TMPDIR="$temporary/socket" "$TMUX_BINARY" -L "$socket_name" list-keys -T prefix 2>/dev/null || true)"
      [[ "$output" == *display-popup* && "$output" == *keybindings.txt* && "$output" != *omarchy-menu-tmux-keybindings* ]] || status=1
    fi
  fi
  ((status == 0)) || die 'accepted tmux configuration failed isolated runtime parsing or effective-option validation'
)

preflight_tmux() {
  register_tmux_area
  validate_tmux_closure
  if [[ "$MODE" == remove ]]; then
    if [[ "$SELECTED_PROFILE" == omarchy ]]; then
      validate_tmux_runtime
      validate_home_parent_chain "$HOME/$TMUX_CONFIG"
      validate_tmux_config_file "$HOME/$TMUX_CONFIG" 'native tmux config'
      validate_tmux_parse
    fi
    lean_preflight_area remove
    return
  fi
  validate_tmux_runtime
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    validate_home_parent_chain "$HOME/$TMUX_CONFIG"
    validate_tmux_config_file "$HOME/$TMUX_CONFIG" 'native tmux config'
  fi
  validate_tmux_parse
  lean_preflight_area "$MODE"
}

apply_tmux() {
  register_tmux_area
  validate_tmux_closure
  validate_tmux_runtime
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    validate_home_parent_chain "$HOME/$TMUX_CONFIG"
    validate_tmux_config_file "$HOME/$TMUX_CONFIG" 'native tmux config'
  fi
  validate_tmux_parse
  lean_apply_area
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    log 'validated package-owned native tmux; no files or deployment state were written'
  else
    log "applied Ubuntu tmux baseline, portable help adapter, and selector; install the fallback manually if needed with: mise install $TMUX_SELECTOR"
  fi
}

remove_tmux() {
  register_tmux_area
  validate_tmux_closure
  if [[ "$SELECTED_PROFILE" == omarchy ]]; then
    validate_tmux_runtime
    validate_home_parent_chain "$HOME/$TMUX_CONFIG"
    validate_tmux_config_file "$HOME/$TMUX_CONFIG" 'native tmux config'
    validate_tmux_parse
  fi
  lean_remove_area
  log 'removed only exact managed tmux package links; retained plugins, resurrect data, sockets, sessions, and runtime state'
}
